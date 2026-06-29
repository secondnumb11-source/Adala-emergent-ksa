#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/archive.e2e.mjs — اختبار شامل لمسار الأرشيف:
 *   عميل → قضية → رفع مستند → التحقق من audit_log + تاريخ الانتهاء (powers_of_attorney).
 * المتغيرات: VITE_SUPABASE_URL, VITE_SUPABASE_PUBLISHABLE_KEY, TEST_USER_EMAIL, TEST_USER_PASSWORD
 */
import { createClient } from '@supabase/supabase-js';
import { setTimeout as wait } from 'node:timers/promises';
import process from 'node:process';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.VITE_SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_ANON_KEY;
const EMAIL = process.env.TEST_USER_EMAIL || 'e2e@example.com';
const PASSWORD = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';
const BUCKET = 'case-documents';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

async function main() {
  if (!SUPABASE_URL || !SUPABASE_KEY) fail('Supabase env vars غير معرّفة');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  let { data: signIn, error: e1 } = await sb.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
  if (e1) {
    const { data: up, error: e2 } = await sb.auth.signUp({ email: EMAIL, password: PASSWORD });
    if (e2) fail('تعذّر تسجيل الدخول/الإنشاء', e2);
    signIn = up;
  }
  const uid = signIn?.user?.id;
  if (!uid) fail('لا توجد جلسة');
  ok(`دخول كـ ${EMAIL}`);

  // 1) إنشاء عميل
  const clientName = `E2E Archive ${Date.now()}`;
  const { data: client, error: cErr } = await sb.from('clients')
    .insert({ owner_id: uid, full_name: clientName, phone: '+966500000000' })
    .select('id, full_name').single();
  if (cErr) fail('إنشاء عميل', cErr);
  ok(`عميل: ${client.full_name}`);

  // 2) إنشاء قضية
  const caseNumber = `E2E-${Date.now()}`;
  const { data: legalCase, error: kErr } = await sb.from('cases')
    .insert({ owner_id: uid, client_id: client.id, case_number: caseNumber, title: 'قضية اختبار e2e' })
    .select('id, case_number, title').single();
  if (kErr) fail('إنشاء قضية', kErr);
  ok(`قضية: ${legalCase.case_number}`);

  // 3) رفع مستند إلى storage + إدخال في جدول documents
  const path = `${uid}/${legalCase.id}/${Date.now()}-sample.txt`;
  const fileBlob = new Blob(['hello e2e archive'], { type: 'text/plain' });
  const { error: upErr } = await sb.storage.from(BUCKET).upload(path, fileBlob, { upsert: false, contentType: 'text/plain' });
  if (upErr) fail('رفع الملف إلى التخزين', upErr);
  const { data: doc, error: dErr } = await sb.from('documents').insert({
    owner_id: uid, case_id: legalCase.id, doc_type: 'other',
    title: 'sample.txt', storage_path: path, file_name: 'sample.txt',
    file_size: 17, mime_type: 'text/plain',
  }).select('id, title, storage_path').single();
  if (dErr) fail('إدخال صف documents', dErr);
  ok(`مستند: ${doc.title} (${doc.id})`);

  // 4) تسجيل audit_log للعملية
  const auditAction = 'document.upload';
  const { error: auErr } = await sb.from('audit_log').insert({
    actor_id: uid, action: auditAction, entity: 'documents', entity_id: doc.id,
    metadata: { case_id: legalCase.id, file_name: 'sample.txt' },
  });
  if (auErr) fail('كتابة audit_log', auErr);

  let auditRow = null;
  for (let i = 0; i < 10; i++) {
    const { data } = await sb.from('audit_log')
      .select('id, action, entity_id').eq('actor_id', uid).eq('action', auditAction)
      .eq('entity_id', doc.id).maybeSingle();
    if (data) { auditRow = data; break; }
    await wait(200);
  }
  if (!auditRow) fail('سجل التدقيق لم يظهر');
  ok(`audit_log ✓ (${auditRow.id})`);

  // 5) إنشاء توكيل (powers_of_attorney) بتاريخ انتهاء قريب — يجب أن يدخل نافذة التنبيه (≤30 يوم)
  const exp = new Date(); exp.setDate(exp.getDate() + 14);
  const { data: poa, error: pErr } = await sb.from('powers_of_attorney').insert({
    owner_id: uid, client_id: client.id,
    wakalah_number: `WK-${Date.now()}`,
    issue_date: new Date().toISOString().slice(0, 10),
    expiry_date: exp.toISOString().slice(0, 10),
    scope: 'e2e',
  }).select('id, expiry_date').single();
  if (pErr) fail('إنشاء توكيل', pErr);
  const daysLeft = Math.ceil((new Date(poa.expiry_date) - new Date()) / 86400000);
  if (daysLeft > 30) fail(`expiry_date خارج نافذة التنبيه (${daysLeft} يوم)`);
  ok(`توكيل بتاريخ انتهاء خلال ${daysLeft} يوم`);

  // 6) تنظيف
  await sb.storage.from(BUCKET).remove([path]);
  await sb.from('documents').delete().eq('id', doc.id);
  await sb.from('powers_of_attorney').delete().eq('id', poa.id);
  await sb.from('cases').delete().eq('id', legalCase.id);
  await sb.from('clients').delete().eq('id', client.id);
  await sb.auth.signOut();
  ok('تنظيف');
  console.log('\n\x1b[32mPASS\x1b[0m — مسار الأرشيف كامل (عميل/قضية/مستند/تدقيق/انتهاء).');
}
main().catch((e) => fail('استثناء', e));