-- Fix missing columns discovered during audit
-- Date: 2026-06-29

-- 1. Add status column to client_inquiries
ALTER TABLE public.client_inquiries 
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'open';

-- 2. Add subject column to employee_messages
ALTER TABLE public.employee_messages 
ADD COLUMN IF NOT EXISTS subject TEXT;

-- 3. Add portal_username column to employees
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS portal_username TEXT;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_client_inquiries_status 
ON public.client_inquiries(status);

CREATE INDEX IF NOT EXISTS idx_employee_messages_subject 
ON public.employee_messages(subject);

CREATE INDEX IF NOT EXISTS idx_employees_portal_username 
ON public.employees(portal_username);
