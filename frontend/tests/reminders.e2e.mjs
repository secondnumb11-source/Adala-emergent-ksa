#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/reminders.e2e.mjs — يتحقق من أن enqueue_session_reminders تنشئ تذكيرًا
 * للجلسات الواقعة ضمن النوافذ [7, 24, 48] ساعة.
 */
import { createClient } from '@supabase/supabase-js';
import { setTimeout as wait } from 'node:timers/promises';
import process from 'node:process';

const URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.VITE_SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_ANON_KEY;
const EMAIL = process.env.TEST_USER_EMAIL || 'e2e@example.com';
const PASSWORD = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

async function main() {
  if (!URL || !KEY) fail('Supabase env vars');
  const sb = createClient(URL, KEY, { auth: { persistSession: false } });
  let { data: signIn, error } = await sb.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
  if (error) {
    const r = await sb.auth.signUp({ email: EMAIL, password: PASSWORD });
    if (r.error) fail('auth', r.error);
    signIn = r.data;
  }
  const uid = signIn.user.id;
  ok(`دخول ${EMAIL}`);

  // أنشئ عميل + قضية + جلسة بعد 24 ساعة بالضبط (داخل نافذة 24h)
  const cl = await sb.from('clients').insert({ owner_id: uid, full_name: `Rem ${Date.now()}` }).select('id').single();
  if (cl.error) fail('client', cl.error);
  const kase = await sb.from('cases').insert({
    owner_id: uid, client_id: cl.data.id,
    case_number: `REM-${Date.now()}`, title: 'reminder test',
  }).select('id').single();
  if (kase.error) fail('case', kase.error);

  const when = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const sess = await sb.from('sessions').insert({
    owner_id: uid, case_id: kase.data.id,
    session_date: when.toISOString(), status: 'scheduled',
    court: 'محكمة الاختبار', purpose: 'e2e',
  }).select('id, session_date').single();
  if (sess.error) fail('session', sess.error);
  ok(`جلسة عند ${sess.data.session_date}`);

  // استدعاء الدالة يدوياً (محاكاة لـ pg_cron)
  const { data: enqueued, error: rpcErr } = await sb.rpc('enqueue_session_reminders');
  if (rpcErr) fail('enqueue_session_reminders', rpcErr);
  ok(`enqueue_session_reminders أعاد ${enqueued}`);

  // تحقق أن التذكير الخاص بهذه الجلسة في session_reminders
  let rem = null;
  for (let i = 0; i < 8; i++) {
    const { data } = await sb.from('session_reminders')
      .select('id, lead_hours, session_id').eq('session_id', sess.data.id).maybeSingle();
    if (data) { rem = data; break; }
    await wait(250);
  }
  if (!rem) fail('لم يُنشأ تذكير للجلسة ضمن نافذة 24h');
  if (rem.lead_hours !== 24) fail(`lead_hours غير متوقع: ${rem.lead_hours}`);
  ok(`session_reminders ✓ (lead=${rem.lead_hours}h)`);

  // idempotent: تشغيل ثاني لا ينتج تكرار
  await sb.rpc('enqueue_session_reminders');
  const dup = await sb.from('session_reminders').select('id', { count: 'exact', head: true }).eq('session_id', sess.data.id);
  if ((dup.count ?? 0) !== 1) fail(`تكرار التذكيرات: count=${dup.count}`);
  ok('idempotent — لا تكرار');

  // تنظيف
  await sb.from('session_reminders').delete().eq('session_id', sess.data.id);
  await sb.from('sessions').delete().eq('id', sess.data.id);
  await sb.from('cases').delete().eq('id', kase.data.id);
  await sb.from('clients').delete().eq('id', cl.data.id);
  await sb.auth.signOut();
  console.log('\n\x1b[32mPASS\x1b[0m — تذكيرات الجلسات تُجدول داخل النافذة.');
}
main().catch((e) => fail('استثناء', e));