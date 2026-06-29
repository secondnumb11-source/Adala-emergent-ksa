#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/portal.e2e.mjs — اختبار شامل لبوابة العملاء + التفضيلات + سجل التدقيق.
 * المتغيرات البيئية:
 *   VITE_SUPABASE_URL, VITE_SUPABASE_PUBLISHABLE_KEY
 *   TEST_USER_EMAIL, TEST_USER_PASSWORD
 */

import { createClient } from '@supabase/supabase-js';
import { setTimeout as wait } from 'node:timers/promises';
import process from 'node:process';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SUPABASE_KEY =
  process.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  process.env.VITE_SUPABASE_ANON_KEY ||
  process.env.SUPABASE_ANON_KEY;
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'e2e@example.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

async function main() {
  if (!SUPABASE_URL || !SUPABASE_KEY) fail('متغيرات Supabase غير معرّفة.');
  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) تسجيل الدخول / إنشاء حساب
  let { data: signIn, error: signInErr } = await supabase.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
  if (signInErr) {
    const { data: signUp, error: signUpErr } = await supabase.auth.signUp({ email: TEST_EMAIL, password: TEST_PASSWORD });
    if (signUpErr) fail('تعذّر إنشاء/تسجيل دخول المستخدم', signUpErr);
    signIn = signUp;
  }
  if (!signIn?.user?.id) fail('لم يتم الحصول على جلسة مصدّقة');
  const uid = signIn.user.id;
  ok(`تسجيل الدخول كـ ${signIn.user.email}`);

  // 2) ضمان وجود عميل + انتظار اكتمال التحميل
  let { data: clients, error: listErr } = await supabase
    .from('clients').select('id, full_name, portal_access_code').order('created_at', { ascending: false });
  if (listErr) fail('قراءة قائمة العملاء فشلت', listErr);
  if (!clients || clients.length === 0) {
    const { data: created, error: cErr } = await supabase
      .from('clients').insert({ full_name: 'عميل اختبار البوابة', owner_id: uid }).select().single();
    if (cErr) fail('تعذّر إنشاء عميل', cErr);
    clients = [created];
  }
  let primary = null;
  for (let i = 0; i < 10; i++) {
    const { data, error } = await supabase.from('clients')
      .select('id, full_name, portal_access_code').eq('id', clients[0].id).maybeSingle();
    if (error) fail('التحقق من تحميل العميل', error);
    if (data) { primary = data; break; }
    await wait(250);
  }
  if (!primary) fail('قائمة العملاء لم تكتمل تحميلها');
  ok(`اكتمل تحميل قائمة العملاء (${clients.length}) — الأساسي: ${primary.full_name}`);

  // 3) حفظ إعدادات البوابة
  const code = `PORTAL-${Date.now().toString(36).toUpperCase()}`;
  const { data: updated, error: uErr } = await supabase.from('clients')
    .update({ portal_access_code: code }).eq('id', primary.id)
    .select('id, portal_access_code').single();
  if (uErr || updated?.portal_access_code !== code) fail('فشل حفظ إعدادات البوابة', uErr);
  ok(`حُفظت إعدادات البوابة (${code})`);

  // 4) قراءة لاحقة
  const { data: verify, error: vErr } = await supabase.from('clients')
    .select('portal_access_code').eq('id', primary.id).single();
  if (vErr || verify.portal_access_code !== code) fail('قيمة البوابة لم تُزامَن');
  ok('تأكدت قيمة البوابة بعد إعادة القراءة');

  // 5) حفظ تفضيلات الإشعارات (notification_preferences)
  const prefsPayload = {
    owner_id: uid,
    channels: { whatsapp: true, sms: false, email: true },
    sessions: { enabled: true, lead_hours: [24, 1] },
    tasks: { enabled: true, lead_hours: [24] },
    appeals: { enabled: true, lead_days: [7, 3, 1] },
    quiet_hours: { enabled: false, start: '22:00', end: '07:00' },
  };
  const { error: prefErr } = await supabase
    .from('notification_preferences')
    .upsert(prefsPayload, { onConflict: 'owner_id' });
  if (prefErr) fail('فشل حفظ تفضيلات الإشعارات', prefErr);

  let prefRow = null;
  for (let i = 0; i < 10; i++) {
    const { data, error } = await supabase
      .from('notification_preferences')
      .select('channels, sessions, tasks, appeals, quiet_hours')
      .eq('owner_id', uid).maybeSingle();
    if (error) fail('قراءة تفضيلات الإشعارات', error);
    if (data) { prefRow = data; break; }
    await wait(200);
  }
  if (!prefRow) fail('لم يتم العثور على تفضيلات الإشعارات بعد الحفظ');
  if (prefRow.channels?.email !== true) fail('تفضيلات الإشعارات لم تُحفظ بشكل صحيح');
  ok('حُفظت وقُرئت notification_preferences بنجاح');

  // 6) إضافة سطر إلى audit_log والتحقق من قراءته
  const action = `e2e_test_${Date.now()}`;
  const { error: auditInsErr } = await supabase.from('audit_log').insert({
    actor_id: uid,
    action,
    entity: 'clients',
    entity_id: primary.id,
    metadata: { test: true, code },
  });
  if (auditInsErr) fail('تعذّر كتابة سطر في audit_log', auditInsErr);

  let auditRow = null;
  for (let i = 0; i < 10; i++) {
    const { data, error } = await supabase.from('audit_log')
      .select('id, action, actor_id, entity, entity_id')
      .eq('actor_id', uid).eq('action', action).maybeSingle();
    if (error) fail('قراءة audit_log', error);
    if (data) { auditRow = data; break; }
    await wait(200);
  }
  if (!auditRow) fail('سطر audit_log لم يظهر بعد الكتابة');
  ok(`سطر audit_log تم توليده وقراءته (action=${action})`);

  await supabase.auth.signOut();
  console.log('\n\x1b[32mPASS\x1b[0m — البوابة + التفضيلات + سجل التدقيق تعمل بنجاح.');
}

main().catch((e) => fail('استثناء غير متوقَّع', e));
