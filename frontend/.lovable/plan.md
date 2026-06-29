# خطة التحقق وإكمال النواقص

سأقسم العمل إلى 6 محاور، أبدأ كل واحد بفحص ما هو موجود فعلًا ثم أكمل النقص فقط (لا أعيد بناء ما يعمل).

## 1. منطق `read_at` و `typing` في الدردشة

**فحص:** `src/routes/_authenticated/app.team-chat.tsx`, `app.messages.tsx`, `app.inquiries.tsx` + `client-inquiries.functions.ts`.

**التنفيذ المتوقع:**
- تحديث `read_at` يستخدم `UPDATE ... WHERE read_at IS NULL AND author_id <> auth.uid()` (idempotent — لا تكرار عند إعادة فتح المحادثة).
- جدول `typing_indicators` (أو presence channel) مع `cleanup` عبر:
  - `presence` channel من Supabase مع `onLeave` يمسح تلقائيًا.
  - + `beforeunload` + `visibilitychange` + heartbeat كل 5ث (سجل يُعتبر منتهيًا بعد 10ث).
  - `removeChannel` في `useEffect` cleanup.

## 2. عدّاد غير المقروء لقائمة محادثات الفريق

**فحص:** `app.team-chat.tsx` — هل توجد قائمة محادثات + بادج عدد؟

**التنفيذ:**
- `unread_count` لكل محادثة = COUNT حيث `author_id <> me AND read_at IS NULL`.
- اشتراك realtime على `team_messages` (INSERT يزيد، UPDATE على `read_at` ينقص).
- يظهر كبادج ذهبي بجوار اسم كل محادثة، يختفي عند الفتح.

## 3. واجهة الاختيار المتعدد لاقتراحات نهاية كل مرحلة

**فحص:** أين تظهر الاقتراحات الحالية (AI suggestions عند اكتمال مرحلة قضية/مهمة)؟ على الأرجح في `ai-generator.tsx` أو ضمن `app.cases`.

**التنفيذ:**
- استبدال زر «تنفيذ» لكل اقتراح بـ Checkbox + شريط سفلي ثابت «تنفيذ المختار (n)».
- زر واحد يجمع الاختيارات ويرسلها دفعة واحدة لـ server function تنفّذها بالترتيب.

## 4. سجل تدقيق لتغييرات قالب رسالة الترحيب

**فحص:** هل يوجد `welcome_template` في `office_settings` أو ما يشبهه؟ وهل يوجد جدول `audit_log` عام؟

**التنفيذ (migration):**
```sql
CREATE TABLE public.welcome_template_audit (
  id uuid PK, owner_id uuid, changed_by uuid,
  old_value text, new_value text, changed_at timestamptz
);
-- GRANTs + RLS: owner يقرأ فقط سجل مكتبه
-- TRIGGER على UPDATE لجدول office_settings/welcome_template
```
+ صفحة عرض السجل (من/إلى/الوقت/المستخدم).

## 5. معاينة مباشرة لرسالة الترحيب

**فحص:** محرر القالب الحالي (غالبًا في `app.client-portal.tsx` أو `app.settings`).

**التنفيذ:**
- لوحة جانبية تعرض الرسالة بعد استبدال `{name}`, `{code}`, `{portal_url}` بقيم تجريبية.
- تحديث فوري عند الكتابة (useMemo)، قبل الحفظ.

## 6. تدقيق الـ SQL Schema الكامل

**فحص جدول-جدول:** clients, employees, cases, powers_of_attorney, national_ids, execution_requests, tasks, sessions, documents, client_inquiries, team_messages, notifications, user_roles, audit_log, office_settings, najiz_sync_*.

لكل جدول أتحقق من:
- وجوده + كل الأعمدة الضرورية (لا نواقص تمنع INSERT).
- `GRANT` صحيح للأدوار.
- `RLS enabled` + policies للقراءة/الكتابة.
- FK + indexes.
- triggers needed (updated_at, audit).

**النتيجة:** تقرير مختصر + migration واحدة تجمع كل التصحيحات الناقصة (أعمدة مفقودة, GRANTs ناقصة, policies مفقودة).

---

## تفاصيل تقنية

- كل migration جديدة تتبع نمط `GRANT` ثم `ENABLE RLS` ثم `POLICY`.
- استخدام `has_role()` security definer للسياسات الإدارية (تجنب recursion).
- typing عبر Supabase Realtime Presence (لا حاجة لجدول مستقل = تنظيف تلقائي عند disconnect).
- audit عبر trigger في Postgres (مضمون حتى لو عدّل أحد عبر SQL مباشرة).

## الترتيب المقترح للتنفيذ

1. فحص شامل (قراءة 8-10 ملفات + كل migrations) — جولة واحدة موازية.
2. كتابة migration واحدة تجمع: جدول audit + أي أعمدة/grants/policies ناقصة.
3. تعديلات الواجهة (الـ 5 محاور الأولى) بالتوازي قدر الإمكان.
4. تشغيل typecheck + تقرير نهائي للمستخدم بما تم وما يحتاج تشغيل migration يدويًا.

## ملاحظة

هذا حجم كبير (≈12–20 ملف). سأنفّذ كل المحاور في رد واحد بعد موافقتك، لكن لو رغبت بالتقسيم — مثلاً تنفيذ المحاور 1+2+3 أولًا ثم 4+5+6 — أخبرني.
