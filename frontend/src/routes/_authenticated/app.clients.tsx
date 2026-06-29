import { createFileRoute } from "@tanstack/react-router";
import { useState, useMemo } from "react";
import { Users, Phone, Mail, IdCard, MapPin, Pencil, Trash2, Search } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { CrudDialog, AddButton, type Field } from "@/components/crud-dialog";
import { Input } from "@/components/ui/input";
import { useList, useUpsert, useDelete } from "@/lib/data-hooks";

export const Route = createFileRoute("/_authenticated/app/clients")({
  component: ClientsPage,
});

const fields: Field[] = [
  { name: "full_name", label: "الاسم الكامل", required: true },
  { name: "national_id", label: "رقم الهوية / السجل" },
  { name: "phone", label: "رقم الجوال", type: "tel" },
  { name: "email", label: "البريد الإلكتروني", type: "email" },
  { name: "address", label: "العنوان", type: "textarea", full: true },
  { name: "notes", label: "ملاحظات", type: "textarea", full: true },
];

function ClientsPage() {
  const { data: rows = [], isLoading } = useList<any>("clients");
  const upsert = useUpsert("clients");
  const del = useDelete("clients");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [q, setQ] = useState("");

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter((r) =>
      `${r.full_name ?? ""} ${r.national_id ?? ""} ${r.phone ?? ""} ${r.email ?? ""}`
        .toLowerCase().includes(s),
    );
  }, [rows, q]);

  return (
    <>
      <PageHeader icon={Users} title="إدارة العملاء" subtitle={`${rows.length} عميل مسجل`}
        action={<AddButton label="إضافة عميل" onClick={() => { setEditing(null); setOpen(true); }} />} />

      <div className="relative mb-4 max-w-md">
        <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input placeholder="بحث عن عميل..." value={q} onChange={(e) => setQ(e.target.value)}
          className="text-right pr-9" />
      </div>

      <CrudDialog open={open} onOpenChange={setOpen} title={editing ? "تعديل عميل" : "عميل جديد"}
        fields={fields} initial={editing ?? {}}
        loading={upsert.isPending}
        onSubmit={async (v) => {
          await upsert.mutateAsync({
            ...v,
            id: editing?.id,
          });
        }} />

      {isLoading ? (
        <p className="text-center text-muted-foreground py-10">جارٍ التحميل...</p>
      ) : filtered.length === 0 ? (
        <div className="card-luxe p-12 text-center text-white/70">
          {rows.length === 0 ? "لا يوجد عملاء بعد — استخدم زر إضافة عميل" : "لا توجد نتائج مطابقة"}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {filtered.map((r) => (
            <div key={r.id} className="card-luxe aspect-square flex flex-col p-5 relative">
              <div className="flex items-start justify-between gap-2 relative z-10">
                <div className="grid h-14 w-14 place-items-center rounded-xl bg-gradient-to-br from-gold to-gold/60 text-primary shadow-md shrink-0 text-lg font-extrabold">
                  {(r.full_name || "؟").trim().charAt(0)}
                </div>
              </div>

              <div className="mt-3 flex-1 min-h-0 relative z-10">
                <div className="text-[10px] uppercase tracking-[0.25em] text-gold/80">العميل</div>
                <div className="mt-0.5 text-base font-extrabold text-white truncate" title={r.full_name}>
                  {r.full_name || "—"}
                </div>

                <dl className="mt-3 space-y-1.5 text-[12px] text-white/80">
                  <Row icon={IdCard} label="الهوية" value={r.national_id} />
                  <Row icon={Phone} label="الجوال" value={r.phone} />
                  <Row icon={Mail} label="البريد" value={r.email} />
                  <Row icon={MapPin} label="العنوان" value={r.address} />
                </dl>
                {r.notes && (
                  <div className="text-[11px] text-white/65 line-clamp-2 pt-2 border-t border-white/10 mt-2">
                    {r.notes}
                  </div>
                )}
              </div>

              <div className="mt-3 grid grid-cols-2 gap-1.5 relative z-10">
                <button onClick={() => { setEditing(r); setOpen(true); }}
                  className="h-8 rounded-lg border border-white/15 bg-white/5 text-white/85 hover:bg-white/10 grid place-items-center gap-1 text-xs flex-row inline-flex">
                  <Pencil className="h-3.5 w-3.5" /> تعديل
                </button>
                <button onClick={() => { if (confirm(`حذف العميل ${r.full_name}؟`)) del.mutate(r.id); }}
                  className="h-8 rounded-lg border border-rose-400/30 bg-rose-400/10 text-rose-300 hover:bg-rose-400/20 grid place-items-center gap-1 text-xs flex-row inline-flex">
                  <Trash2 className="h-3.5 w-3.5" /> حذف
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function Row({ icon: Icon, label, value }: { icon: any; label: string; value: any }) {
  return (
    <div className="flex items-center gap-1.5 truncate">
      <Icon className="h-3 w-3 text-gold/70 shrink-0" />
      <span className="text-white/55 shrink-0">{label}:</span>
      <span className="truncate text-white/90">{value || "—"}</span>
    </div>
  );
}
