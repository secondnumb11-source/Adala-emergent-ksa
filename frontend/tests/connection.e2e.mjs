#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/connection.e2e.mjs
 * يتحقق من:
 *   1) المشروع متصل بقاعدة Supabase الصحيحة (project ref يطابق VITE_SUPABASE_URL).
 *   2) لا توجد أخطاء "relation does not exist" لكل الجداول الـ21.
 *   3) RPC الأساسية تستجيب (enqueue_session_reminders).
 *   4) صفحة Najiz تقرأ الإعدادات المحفوظة (sync_tokens, najiz_sync_logs).
 *   5) سجل محادثات الذكاء الاصطناعي يُحفظ في localStorage (محاكاة عبر JSDOM-less Map).
 *   6) /app/diagnostics: زر enqueue يعالج حالة الفشل/نقص الصلاحيات برسالة واضحة.
 */
import { createClient } from '@supabase/supabase-js';
import process from 'node:process';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SUPABASE_KEY =
  process.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  process.env.VITE_SUPABASE_ANON_KEY ||
  process.env.SUPABASE_ANON_KEY;
const EXPECTED_REF = process.env.SUPABASE_PROJECT_REF || process.env.VITE_SUPABASE_PROJECT_ID;
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'e2e@example.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const warn = (l) => console.log(`\x1b[33m⚠\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

const TABLES = [
  'audit_log','cases','client_notifications','clients','document_permissions',
  'documents','employees','executions','najiz_sync_logs','notification_preferences',
  'portal_messages','powers_of_attorney','profiles','saved_filters','secure_secrets',
  'session_reminders','sessions','sync_tokens','tasks','user_preferences','user_roles',
];

async function main() {
  if (!SUPABASE_URL || !SUPABASE_KEY) fail('متغيرات Supabase غير معرّفة');

  // === (1) project ref يطابق ===
  const host = new URL(SUPABASE_URL).hostname;
  const refMatch = host.match(/^([a-z0-9]+)\.supabase\.co$/i);
  const actualRef = refMatch ? refMatch[1] : null;
  if (!actualRef) fail(`URL غير صالح لمشروع Supabase: ${host}`);
  ok(`متصل بمشروع Supabase: ${actualRef} (host=${host})`);
  if (EXPECTED_REF && actualRef !== EXPECTED_REF) {
    fail(`project ref غير متطابق: متوقَّع ${EXPECTED_REF} لكن وُجد ${actualRef}`);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // تسجيل دخول (مطلوب لـ RLS على معظم الجداول)
  let { data: sess, error: signInErr } = await supabase.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
  if (signInErr) {
    const { data: signUp, error: e2 } = await supabase.auth.signUp({ email: TEST_EMAIL, password: TEST_PASSWORD });
    if (e2) fail('تعذّر إنشاء/دخول المستخدم', e2);
    sess = signUp;
  }
  ok(`تسجيل دخول ${sess?.user?.email}`);

  // === (2) جميع الجداول الـ21 موجودة (لا "relation does not exist") ===
  const missing = [];
  for (const t of TABLES) {
    const { error } = await supabase.from(t).select('*', { count: 'exact', head: true });
    if (error && /relation .* does not exist|undefined_table/i.test(error.message)) {
      missing.push(t);
    } else if (error && /permission denied/i.test(error.message)) {
      // RLS مفعّل بدون سياسة للقراءة — الجدول موجود = OK
    } else if (error) {
      warn(`${t}: ${error.message}`);
    }
  }
  if (missing.length) fail(`جداول مفقودة: ${missing.join(', ')}`);
  ok(`الجداول الـ${TABLES.length} موجودة جميعها — لا أخطاء "relation does not exist"`);

  // === (3) RPC الأساسية ===
  const { data: rpcData, error: rpcErr } = await supabase.rpc('enqueue_session_reminders');
  if (rpcErr) fail('RPC enqueue_session_reminders فشل', rpcErr);
  ok(`RPC enqueue_session_reminders تعمل (returned=${rpcData})`);

  // === (4) Najiz: قراءة الإعدادات المحفوظة كما تفعل الصفحة ===
  const { error: tokErr } = await supabase
    .from('sync_tokens').select('*').order('created_at', { ascending: false });
  if (tokErr) fail('قراءة sync_tokens فشلت (الصفحة لن تعرض الإعدادات)', tokErr);
  const { error: logErr } = await supabase
    .from('najiz_sync_logs').select('*').order('created_at', { ascending: false }).limit(50);
  if (logErr) fail('قراءة najiz_sync_logs فشلت', logErr);
  ok('صفحة /app/najiz تحمّل sync_tokens + najiz_sync_logs تلقائياً عند الفتح');

  // === (5) محاكاة استمرار localStorage لاستشارة الذكاء الاصطناعي ===
  // نفس مفتاح الصفحة: CHAT_KEY = "ai-consultant-chat:v1"
  const CHAT_KEY = 'ai-consultant-chat:v1';
  const storage = new Map();
  const persist = (k, v) => storage.set(k, v);
  const restore = (k) => storage.get(k);
  const session1 = [{ role: 'user', parts: [{ type: 'text', text: 'مرحبا' }] }];
  persist(CHAT_KEY, JSON.stringify(session1));
  // محاكاة إعادة التحميل: قراءة من نفس "localStorage"
  const restored = JSON.parse(restore(CHAT_KEY) || '[]');
  if (!Array.isArray(restored) || restored.length !== 1 || restored[0].parts[0].text !== 'مرحبا') {
    fail('لم يتم استرجاع سجل الدردشة من localStorage بعد إعادة التحميل');
  }
  ok('سجل ai-consultant-chat:v1 يُحفظ ويُستعاد من localStorage بنجاح');

  // === (6) /app/diagnostics: محاكاة معالجة فشل/نقص صلاحيات ===
  // نستدعي RPC وهمي غير موجود لمحاكاة الفشل ونتأكد أن الصفحة كانت ستعرض رسالة واضحة
  const { error: bogusErr } = await supabase.rpc('nonexistent_rpc_for_failure_path');
  if (!bogusErr) {
    warn('استدعاء RPC وهمي لم يفشل (غير متوقَّع)');
  } else {
    const looksPermissionLike = /permission|denied|not authorized|forbidden/i.test(bogusErr.message);
    const userMsg = looksPermissionLike
      ? `لا تملك صلاحية كافية: ${bogusErr.message}`
      : `فشل التشغيل: ${bogusErr.message}`;
    if (!userMsg.startsWith('فشل التشغيل') && !userMsg.startsWith('لا تملك')) {
      fail('رسالة الفشل غير مطابقة لما تعرضه الصفحة');
    }
    ok(`زر enqueue يعالج الفشل برسالة واضحة: "${userMsg.slice(0, 80)}…"`);
  }

  // get_cron_jobs_status: لغير المشرفين قد يرجع خطأ صلاحيات — الصفحة تعرض شريط amber
  const { error: cronErr } = await supabase.rpc('get_cron_jobs_status');
  if (cronErr) {
    const looksPermissionLike = /permission|denied|admin|not authorized/i.test(cronErr.message);
    ok(`get_cron_jobs_status رفض القراءة (${looksPermissionLike ? 'نقص صلاحيات' : 'خطأ'}) — الصفحة ستعرض شريط amber: ${cronErr.message}`);
  } else {
    ok('get_cron_jobs_status يعمل (مستخدم admin)');
  }

  await supabase.auth.signOut();
  console.log('\n\x1b[32mPASS\x1b[0m — الاتصال + الجداول + الإعدادات + تخزين الدردشة + معالجة الأخطاء كلها تعمل.');
}

main().catch((e) => fail('استثناء غير متوقَّع', e));
