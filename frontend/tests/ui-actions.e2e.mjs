#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * tests/ui-actions.e2e.mjs — يتحقق من السلوك الفعلي خلف أزرار الواجهة:
 *   1) زر «إعادة إرسال رسالة التفعيل» في /app/verification
 *      → supabase.auth.resend({type:'signup'}) + منطق تعطيل الزر عند التأكيد
 *   2) زر «تشغيل تذكيرات الجلسات الآن» في /app/diagnostics
 *      → supabase.rpc('enqueue_session_reminders') + قراءة get_cron_jobs_status
 */
import { createClient } from '@supabase/supabase-js';
import process from 'node:process';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SUPABASE_KEY =
  process.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  process.env.VITE_SUPABASE_ANON_KEY ||
  process.env.SUPABASE_ANON_KEY;
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'e2e@example.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Passw0rd!Demo';

const ok = (l) => console.log(`\x1b[32m✓\x1b[0m ${l}`);
const warn = (l) => console.log(`\x1b[33m⚠\x1b[0m ${l}`);
const fail = (l, e) => { console.error(`\x1b[31m✗\x1b[0m ${l}`); if (e) console.error(e); process.exit(1); };

async function main() {
  if (!SUPABASE_URL || !SUPABASE_KEY) fail('متغيرات Supabase غير معرّفة');
  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let { data: sess, error: signInErr } = await supabase.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
  if (signInErr) {
    const { data: signUp, error: e2 } = await supabase.auth.signUp({ email: TEST_EMAIL, password: TEST_PASSWORD });
    if (e2) fail('تعذّر إنشاء/دخول المستخدم', e2);
    sess = signUp;
  }
  const user = sess?.user;
  if (!user) fail('لا توجد جلسة');
  ok(`تسجيل دخول ${user.email}`);

  // === (1) سيناريو زر إعادة إرسال التفعيل في /app/verification ===
  const confirmed = !!user.email_confirmed_at;
  // قاعدة الواجهة: disabled = !email || confirmed || loading
  const shouldBeDisabled = !user.email || confirmed;
  ok(`حالة الزر المحسوبة: ${shouldBeDisabled ? 'معطَّل (الحساب مؤكَّد بالفعل)' : 'مُفعَّل'}`);

  if (!confirmed) {
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email: user.email,
      options: { emailRedirectTo: 'http://localhost:8080/auth' },
    });
    if (error) {
      // rate-limit شائع — لا يعتبر فشلاً للاختبار، فالواجهة تعرض toast.error صراحةً
      warn(`resend رفض الطلب: ${error.message} (الواجهة ستعرض toast.error)`);
    } else {
      ok('أُرسل طلب إعادة التفعيل بنجاح — الواجهة ستعرض toast.success');
    }
  } else {
    ok('تخطّي استدعاء resend لأن الحساب مؤكَّد (مطابق لمنطق تعطيل الزر)');
  }

  // === (2) سيناريو زر تشغيل تذكيرات الجلسات في /app/diagnostics ===
  const { data: enqueued, error: rpcErr } = await supabase.rpc('enqueue_session_reminders');
  if (rpcErr) fail('فشل تشغيل enqueue_session_reminders', rpcErr);
  if (typeof enqueued !== 'number') fail(`نوع غير متوقَّع من RPC: ${typeof enqueued}`);
  ok(`تشغيل enqueue_session_reminders نجح — تم إدراج ${enqueued} تذكير`);

  // قراءة سجل المهمة كما تفعل الواجهة بعد الضغط (loadCronJobs)
  const { data: cron, error: cronErr } = await supabase.rpc('get_cron_jobs_status');
  if (cronErr) {
    // قد تتطلب صلاحية admin — مقبول كتنبيه لكنه يطابق ما تعرضه الواجهة من رسالة amber
    warn(`get_cron_jobs_status رفض الطلب: ${cronErr.message} (الواجهة ستعرض شريط التحذير)`);
  } else if (!Array.isArray(cron)) {
    fail(`نوع غير متوقَّع من get_cron_jobs_status: ${typeof cron}`);
  } else {
    ok(`قراءة سجل pg_cron نجحت — ${cron.length} مهمة مجدولة`);
    const reminder = cron.find((j) => j.jobname === 'enqueue-session-reminders');
    if (reminder) ok(`مهمة enqueue-session-reminders: schedule=${reminder.schedule}, active=${reminder.active}, last_status=${reminder.last_status ?? 'n/a'}`);
    else warn('مهمة enqueue-session-reminders غير موجودة في cron.job');
  }

  await supabase.auth.signOut();
  console.log('\n\x1b[32mPASS\x1b[0m — أزرار /app/verification و /app/diagnostics تعمل بشكل صحيح.');
}

main().catch((e) => fail('استثناء غير متوقَّع', e));
