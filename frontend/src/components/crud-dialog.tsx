import { useState, useEffect, type ReactNode } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Loader2, Plus } from "lucide-react";

export type Field = {
  name: string;
  label: string;
  type?: "text" | "number" | "date" | "datetime-local" | "email" | "tel" | "textarea" | "select";
  options?: { value: string; label: string }[];
  required?: boolean;
  placeholder?: string;
  full?: boolean;
};

export function CrudDialog<T extends Record<string, any>>({
  trigger, title, fields, initial, onSubmit, loading, open, onOpenChange,
}: {
  trigger?: ReactNode;
  title: string;
  fields: Field[];
  initial?: Partial<T>;
  onSubmit: (values: Record<string, any>) => Promise<void> | void;
  loading?: boolean;
  open?: boolean;
  onOpenChange?: (v: boolean) => void;
}) {
  const [internalOpen, setInternalOpen] = useState(false);
  const isControlled = open !== undefined;
  const isOpen = isControlled ? open : internalOpen;
  const setOpen = isControlled ? (onOpenChange ?? (() => {})) : setInternalOpen;
  const [values, setValues] = useState<Record<string, any>>({});

  useEffect(() => {
    if (isOpen) setValues({ ...(initial ?? {}) });
  }, [isOpen, initial]);

  const handle = async (e: React.FormEvent) => {
    e.preventDefault();
    await onSubmit(values);
    setOpen(false);
  };

  return (
    <Dialog open={isOpen} onOpenChange={setOpen}>
      {trigger && <DialogTrigger asChild>{trigger}</DialogTrigger>}
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto" dir="rtl">
        <DialogHeader>
          <DialogTitle className="text-right text-xl">{title}</DialogTitle>
          <DialogDescription className="text-right text-xs">جميع الحقول المطلوبة لإتمام العملية</DialogDescription>
        </DialogHeader>
        <form onSubmit={handle} className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
          {fields.map((f) => (
            <div key={f.name} className={f.full ? "md:col-span-2" : ""}>
              <Label className="text-xs font-semibold mb-1.5 block">
                {f.label} {f.required && <span className="text-destructive">*</span>}
              </Label>
              {f.type === "textarea" ? (
                <Textarea
                  value={values[f.name] ?? ""}
                  onChange={(e) => setValues({ ...values, [f.name]: e.target.value })}
                  required={f.required}
                  placeholder={f.placeholder}
                  className="text-right min-h-[80px]"
                />
              ) : f.type === "select" ? (
                <select
                  value={values[f.name] ?? ""}
                  onChange={(e) => setValues({ ...values, [f.name]: e.target.value || null })}
                  required={f.required}
                  className="w-full h-10 rounded-lg border bg-background px-3 text-sm text-right"
                >
                  <option value="">— اختر —</option>
                  {f.options?.map((o) => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </select>
              ) : (
                <Input
                  type={f.type ?? "text"}
                  value={values[f.name] ?? ""}
                  onChange={(e) => setValues({ ...values, [f.name]: f.type === "number" ? (e.target.value ? Number(e.target.value) : null) : e.target.value })}
                  required={f.required}
                  placeholder={f.placeholder}
                  className="text-right"
                />
              )}
            </div>
          ))}
          <DialogFooter className="md:col-span-2 gap-2 mt-2">
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
            <Button type="submit" className="btn-gold" disabled={loading}>
              {loading ? <Loader2 className="h-4 w-4 animate-spin ml-2" /> : null}
              حفظ
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function AddButton({ onClick, label = "إضافة جديد" }: { onClick?: () => void; label?: string }) {
  return (
    <Button onClick={onClick} className="btn-gold gap-2">
      <Plus className="h-4 w-4" />{label}
    </Button>
  );
}
