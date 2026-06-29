# تفعيل المهام المجدولة (pg_cron)

تنفيذ تذكيرات الجلسات تلقائياً يتطلب تفعيل امتداد `pg_cron` و `pg_net` مرة واحدة، ثم إنشاء مهمة دورية تستدعي endpoint عام.

## ١. تفعيل الامتدادات

في Supabase SQL Editor:

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
```

## ٢. حفظ السر في Vault (موصى به)

```sql
SELECT vault.create_secret('YOUR_CRON_SECRET_VALUE', 'CRON_SECRET');
```

استبدل `YOUR_CRON_SECRET_VALUE` بقيمة `CRON_SECRET` المخزّنة في إعدادات المشروع.

## ٣. جدولة المهمة (كل ١٥ دقيقة)

```sql
SELECT cron.schedule(
  'session-reminders',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://project--<PROJECT-ID>.lovable.app/api/public/cron/session-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'CRON_SECRET')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

استبدل `<PROJECT-ID>` بمعرّف مشروعك. صفحة التشخيص `/app/diagnostics` تعرض حالة المهام للمسؤولين.

## ٤. للإلغاء

```sql
SELECT cron.unschedule('session-reminders');
```
