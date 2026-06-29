#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/doc-permissions.e2e.mjs — يتحقق أن RLS على documents + bucket case-documents
 * تمنع المستخدم الآخر من قراءة/تنزيل مستندات قضية لا يملكها.
 * المتغيرات الإضافية: TEST_USER2_EMAIL, TEST_USER2_PASSWORD
 */
import { createClient } from '@supabase/supabase-js';
import process from 'node:process';

const URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.VITE_SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_ANON_KEY;
const E1 = process.env.TEST_USER_EMAIL  || 'e2e@example.com';
const P1 = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';
const E2 = process.env.TEST_USER2_EMAIL  || 'e2e-other@example.com';
const P2 = process.env.TEST_USER2_PASSWORD || 'Passw0rd!Other';
const BUCKET = 'case-documents';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

async function signIn(email, password) {
  const sb = createClient(URL, KEY, { auth: { persistSession: false } });
  let { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) {
    const r = await sb.auth.signUp({ email, password });
    if (r.error) fail(`auth ${email}`, r.error);
    data = r.data;
  }
  return { sb, uid: data.user.id };
}

async function main() {
  if (!URL || !KEY) fail('Supabase env vars غير معرّفة');
  const owner = await signIn(E1, P1);
  ok(`owner=${owner.uid.slice(0, 8)}`);
  const other = await signIn(E2, P2);
  ok(`other=${other.uid.slice(0, 8)}`);
  if (owner.uid === other.uid) fail('المستخدمان متطابقان — استخدم TEST_USER2_*');

  // owner: ينشئ عميل/قضية/مستند
  const cl = await owner.sb.from('clients').insert({ owner_id: owner.uid, full_name: `RLS ${Date.now()}` }).select('id').single();
  if (cl.error) fail('insert client', cl.error);
  const kase = await owner.sb.from('cases').insert({
    owner_id: owner.uid, client_id: cl.data.id,
    case_number: `RLS-${Date.now()}`, title: 'RLS test',
  }).select('id').single();
  if (kase.error) fail('insert case', kase.error);

  const path = `${owner.uid}/${kase.data.id}/${Date.now()}-secret.txt`;
  const up = await owner.sb.storage.from(BUCKET).upload(path, new Blob(['secret']), { contentType: 'text/plain' });
  if (up.error) fail('owner upload', up.error);
  const doc = await owner.sb.from('documents').insert({
    owner_id: owner.uid, case_id: kase.data.id, doc_type: 'other',
    title: 'secret.txt', storage_path: path, file_name: 'secret.txt',
    file_size: 6, mime_type: 'text/plain',
  }).select('id').single();
  if (doc.error) fail('insert doc', doc.error);
  ok('owner أنشأ المستند');

  // other: لا يجب أن يرى المستند في جدول documents
  const seen = await other.sb.from('documents').select('id').eq('id', doc.data.id).maybeSingle();
  if (seen.data) fail('🚨 RLS مكسور: مستخدم آخر يرى مستند ليس له');
  ok('documents RLS يمنع القراءة');

  // other: محاولة تنزيل من storage
  const dl = await other.sb.storage.from(BUCKET).download(path);
  if (!dl.error) fail('🚨 storage RLS مكسور: تنزيل ناجح لمستخدم آخر');
  ok(`storage RLS يمنع التنزيل (${dl.error.message})`);

  // other: محاولة الحذف
  const rm = await other.sb.storage.from(BUCKET).remove([path]);
  // remove يعيد 200 مع قائمة فارغة عند الرفض — تأكد أن الملف ما زال موجودًا
  const stillThere = await owner.sb.storage.from(BUCKET).download(path);
  if (stillThere.error) fail('🚨 الملف اختفى — صلاحيات الحذف مكسورة', rm.error);
  ok('storage RLS يمنع الحذف');

  // تنظيف
  await owner.sb.storage.from(BUCKET).remove([path]);
  await owner.sb.from('documents').delete().eq('id', doc.data.id);
  await owner.sb.from('cases').delete().eq('id', kase.data.id);
  await owner.sb.from('clients').delete().eq('id', cl.data.id);
  await owner.sb.auth.signOut(); await other.sb.auth.signOut();
  console.log('\n\x1b[32mPASS\x1b[0m — صلاحيات case-documents سليمة.');
}
main().catch((e) => fail('استثناء', e));