import { createFileRoute, Link } from "@tanstack/react-router";
import { useState, useMemo } from "react";
import { Receipt, ArrowRight, FileText, CreditCard, ArrowDownToLine, ArrowUpFromLine, Download, Printer, Eye } from "lucide-react";
import { PageHeader } from "@/components/section-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { useList } from "@/lib/data-hooks";
import { toast } from "sonner";
import { loadSettings } from "@/lib/app-settings";
import DOMPurify from "dompurify";

// Escape any string before placing it into raw HTML markup.
const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

// Only http(s) and data:image/* URLs may be used as <img src>; reject javascript:, etc.
const safeImgSrc = (s: unknown) => {
  const v = String(s ?? "").trim();
  if (/^https?:\/\//i.test(v)) return esc(v);
  if (/^data:image\/(png|jpe?g|gif|webp|svg\+xml);base64,[A-Za-z0-9+/=]+$/i.test(v)) return esc(v);
  return "";
};

export const Route = createFileRoute("/_authenticated/app/ai/invoices")({
  component: InvoicesPage,
});

const TYPES = [
  { id: "tax_invoice", title: "فاتورة أتعاب ضريبية", desc: "فاتورة ضريبية (مبسطة/شاملة) مع 15% ضريبة", icon: FileText, color: "from-emerald-500 to-teal-400" },
  { id: "pay_link", title: "رابط دفع إلكتروني", desc: "STC Pay / مدى / Apple Pay", icon: CreditCard, color: "from-blue-500 to-indigo-500" },
  { id: "receipt", title: "سند قبض", desc: "إيصال استلام مبلغ من العميل", icon: ArrowDownToLine, color: "from-amber-500 to-yellow-400" },
  { id: "voucher", title: "سند صرف", desc: "إيصال صرف مبلغ", icon: ArrowUpFromLine, color: "from-rose-500 to-pink-500" },
] as const;
type TypeId = typeof TYPES[number]["id"];

function InvoicesPage() {
  const [type, setType] = useState<TypeId | null>(null);

  return (
    <>
      <PageHeader
        icon={Receipt}
        title="إصدار الفواتير والسندات"
        subtitle="فواتير ضريبية، سندات قبض وصرف، وروابط دفع إلكتروني"
        action={
          <Button asChild variant="outline" size="sm">
            <Link to="/app/ai"><ArrowRight className="h-4 w-4 ml-1" /> العودة</Link>
          </Button>
        }
      />

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {TYPES.map((t) => {
          const active = type === t.id;
          return (
            <button key={t.id} onClick={() => setType(t.id)} className="text-right focus:outline-none">
              <Card className={`card-3d border-none overflow-hidden p-0 transition-all ${active ? "ring-2 ring-gold scale-[1.02]" : ""}`}>
                <div className={`h-24 bg-gradient-to-br ${t.color} grid place-items-center`}>
                  <t.icon className="h-9 w-9 text-white drop-shadow-lg" />
                </div>
                <div className="p-3">
                  <div className="font-bold text-sm mb-0.5">{t.title}</div>
                  <div className="text-[10px] text-muted-foreground leading-tight">{t.desc}</div>
                </div>
              </Card>
            </button>
          );
        })}
      </div>

      {!type && (
        <Card className="card-3d border-none p-10 text-center">
          <Receipt className="h-12 w-12 mx-auto text-muted-foreground/40 mb-3" />
          <p className="text-muted-foreground">اختر نوع المستند المالي لإصداره</p>
        </Card>
      )}

      {type && <InvoiceForm type={type} />}
    </>
  );
}

function InvoiceForm({ type }: { type: TypeId }) {
  const clients = useList<{ id: string; full_name?: string; name?: string }>("clients");
  const cases = useList<{ id: string; title?: string; case_number?: string }>("cases");
  const [client, setClient] = useState("");
  const [caseTitle, setCaseTitle] = useState("");
  const [desc, setDesc] = useState("");
  const [amount, setAmount] = useState(0);
  const [number, setNumber] = useState(`${Date.now().toString().slice(-6)}`);
  const [previewOpen, setPreviewOpen] = useState(false);

  const tax = useMemo(() => +(amount * 0.15).toFixed(2), [amount]);
  const total = useMemo(() => +(amount + tax).toFixed(2), [amount, tax]);

  const buildDoc = () => generateDocument({ type, number, client, caseTitle, desc, amount, tax, total });

  const onPrint = () => {
    // Print the full letterhead document (with the office logo) rather than
    // the on-screen preview, so every printed invoice / receipt / voucher
    // carries the firm's logo on its header.
    const content = buildDoc();
    const w = window.open("", "_blank", "width=820,height=1000");
    if (!w) {
      toast.error("تعذّر فتح نافذة الطباعة — يرجى السماح بالنوافذ المنبثقة");
      return;
    }
    w.document.open();
    w.document.write(content);
    w.document.close();
    w.focus();
    // Wait for the logo image to load before invoking print.
    w.onload = () => {
      setTimeout(() => {
        w.print();
      }, 250);
    };
  };
  const onDownload = () => {
    const content = buildDoc();
    const blob = new Blob([content], { type: "text/html;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${type}-${number}.html`;
    a.click();
    URL.revokeObjectURL(url);
    toast.success("تم التنزيل");
  };

  const onPayLink = () => {
    const link = `https://pay.example.sa/inv/${number}?amount=${total}`;
    navigator.clipboard.writeText(link);
    toast.success("تم نسخ رابط الدفع: " + link);
  };

  return (
    <div className="grid lg:grid-cols-2 gap-6">
      <Card className="card-3d border-none p-6">
        <h3 className="font-bold mb-4">بيانات المستند</h3>
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold mb-1.5 block">رقم المستند</label>
            <Input value={number} onChange={(e) => setNumber(e.target.value)} className="text-right h-10" />
          </div>
          <div>
            <label className="text-xs font-semibold mb-1.5 block">العميل</label>
            <select value={client} onChange={(e) => setClient(e.target.value)} className="w-full h-10 rounded-lg border bg-background px-3 text-sm">
              <option value="">— اختر —</option>
              {clients.data?.map((c) => <option key={c.id} value={c.full_name ?? c.name ?? c.id}>{c.full_name ?? c.name}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold mb-1.5 block">القضية المرتبطة (اختياري)</label>
            <select value={caseTitle} onChange={(e) => setCaseTitle(e.target.value)} className="w-full h-10 rounded-lg border bg-background px-3 text-sm">
              <option value="">— اختر —</option>
              {cases.data?.map((c) => <option key={c.id} value={c.title ?? c.case_number ?? c.id}>{c.title ?? c.case_number}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold mb-1.5 block">الوصف / البيان</label>
            <Textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={4} className="text-right" placeholder="مثال: أتعاب محاماة عن قضية رقم..." />
          </div>
          <div>
            <label className="text-xs font-semibold mb-1.5 block">المبلغ (ر.س قبل الضريبة)</label>
            <Input type="number" value={amount || ""} onChange={(e) => setAmount(Number(e.target.value) || 0)} className="text-right h-10" />
          </div>
        </div>
      </Card>

      <Card className="card-3d border-none p-6 bg-gradient-to-br from-card to-muted/20" id="invoice-preview">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-xl font-extrabold">{TYPES.find((t) => t.id === type)!.title}</h3>
            <div className="text-xs text-muted-foreground mt-1">رقم: {number}</div>
            <div className="text-xs text-muted-foreground">التاريخ: {new Date().toLocaleDateString("ar-SA")}</div>
          </div>
          <div className="grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-primary to-primary/70 text-gold">
            <Receipt className="h-7 w-7" />
          </div>
        </div>

        <div className="space-y-2 text-sm mb-4">
          <div className="flex justify-between"><span className="text-muted-foreground">العميل:</span><span className="font-bold">{client || "—"}</span></div>
          {caseTitle && <div className="flex justify-between"><span className="text-muted-foreground">القضية:</span><span className="font-bold">{caseTitle}</span></div>}
          {desc && <div className="pt-2 border-t"><div className="text-muted-foreground text-xs mb-1">البيان:</div><div>{desc}</div></div>}
        </div>

        <div className="rounded-xl bg-muted/40 p-4 space-y-2 text-sm">
          <div className="flex justify-between"><span>المبلغ الأساسي</span><span className="font-bold">{amount.toLocaleString("ar-SA")} ر.س</span></div>
          {type === "tax_invoice" && (
            <div className="flex justify-between text-muted-foreground"><span>ضريبة القيمة المضافة (15%)</span><span>{tax.toLocaleString("ar-SA")} ر.س</span></div>
          )}
          <div className="flex justify-between text-base pt-2 border-t font-extrabold text-gold">
            <span>الإجمالي</span>
            <span>{(type === "tax_invoice" ? total : amount).toLocaleString("ar-SA")} ر.س</span>
          </div>
        </div>

        <div className="flex gap-2 mt-6">
          <Button onClick={() => setPreviewOpen(true)} variant="outline" className="flex-1"><Eye className="h-4 w-4 ml-1" /> معاينة</Button>
          <Button onClick={onPrint} variant="outline" className="flex-1"><Printer className="h-4 w-4 ml-1" /> طباعة</Button>
          <Button onClick={onDownload} variant="outline" className="flex-1"><Download className="h-4 w-4 ml-1" /> تنزيل</Button>
          {type === "pay_link" && (
            <Button onClick={onPayLink} className="btn-gold flex-1"><CreditCard className="h-4 w-4 ml-1" /> توليد رابط الدفع</Button>
          )}
        </div>
      </Card>

      <Dialog open={previewOpen} onOpenChange={setPreviewOpen}>
        <DialogContent className="max-w-5xl w-[95vw] h-[90vh] p-0 overflow-hidden flex flex-col">
          <DialogHeader className="px-6 py-3 border-b bg-gradient-to-l from-gold/10 to-transparent">
            <DialogTitle className="text-right text-base font-extrabold">
              معاينة قبل الطباعة — {TYPES.find((t) => t.id === type)!.title}
            </DialogTitle>
          </DialogHeader>
          <div className="flex-1 bg-muted/30 overflow-hidden">
            <iframe
              key={`${previewOpen}-${number}-${amount}-${desc}-${client}`}
              title="معاينة المستند"
              srcDoc={previewOpen ? buildDoc() : ""}
              className="w-full h-full bg-white"
            />
          </div>
          <DialogFooter className="px-6 py-3 border-t flex-row gap-2 sm:justify-start">
            <Button onClick={onPrint} className="btn-gold"><Printer className="h-4 w-4 ml-1" /> طباعة</Button>
            <Button onClick={onDownload} variant="outline"><Download className="h-4 w-4 ml-1" /> تنزيل</Button>
            <Button onClick={() => setPreviewOpen(false)} variant="ghost">إغلاق</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function generateDocument(d: {
  type: TypeId; number: string; client: string; caseTitle: string;
  desc: string; amount: number; tax: number; total: number;
}) {
  const title = TYPES.find((t) => t.id === d.type)!.title;
  const s = (() => { try { return loadSettings().office; } catch { return null as any; } })();
  const officeName = s?.arabicName || s?.officeName || "";
  const officeNameEn = s?.officeName && s?.arabicName && s.officeName !== s.arabicName ? s.officeName : "";
  const meta = [
    s?.licenseText && `الترخيص: ${s.licenseText}`,
    s?.crNumber && `س.ت: ${s.crNumber}`,
    s?.taxNumber && `الرقم الضريبي: ${s.taxNumber}`,
    s?.phone && `هاتف: ${s.phone}`,
    s?.email && `بريد: ${s.email}`,
    s?.website && `موقع: ${s.website}`,
  ].filter(Boolean).join(" • ");
  const logoSrc = safeImgSrc(s?.logoDataUrl);
  const logo = logoSrc
    ? `<img src="${logoSrc}" alt="شعار المكتب" style="height:88px;width:88px;object-fit:contain;border-radius:14px;background:#fff;padding:6px;box-shadow:0 6px 20px -10px rgba(15,30,75,.35);border:1.5px solid #e9d68a"/>`
    : `<div style="height:88px;width:88px;border-radius:18px;background:linear-gradient(135deg,#d4a017,#8a6510);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:900;font-size:18px;letter-spacing:.5px;box-shadow:0 8px 24px -10px rgba(212,160,23,.55)">مكتب</div>`;
  const hc = !!s?.printHighContrast;
  const letterhead = `
    <div class="letterhead">
      <div class="lh-top">
        ${logo}
        <div class="lh-info">
          <div class="lh-name">${esc(officeName) || "مكتب المحاماة"}</div>
          ${officeNameEn ? `<div class="lh-name-en">${esc(officeNameEn)}</div>` : ""}
          ${s?.address ? `<div class="lh-line">${esc(s.address)}</div>` : ""}
          ${meta ? `<div class="lh-meta">${esc(meta)}</div>` : ""}
        </div>
        <div class="lh-badge">
          <div class="lh-badge-label">${esc(title)}</div>
          <div class="lh-badge-num">#${esc(d.number)}</div>
        </div>
      </div>
      <div class="lh-rule"><span></span><span></span><span></span></div>
    </div>`;
  const safeFooterHtml = s?.footerHtml
    ? DOMPurify.sanitize(String(s.footerHtml), { FORBID_TAGS: ["script", "style", "iframe", "object", "embed", "form"], FORBID_ATTR: ["onerror", "onload", "onclick", "onmouseover", "onfocus", "onblur", "onchange", "onsubmit", "style"] })
    : "";
  const footer = `<div class="doc-footer">
      <div class="foot-line"><span></span><span></span><span></span></div>
      ${safeFooterHtml ? `<div class="foot-html">${safeFooterHtml}</div>` : ""}
      <div class="foot-sig">
        <div class="sig-box"><div class="sig-label">توقيع المستلم</div><div class="sig-line"></div></div>
        <div class="sig-stamp">ختم المكتب</div>
        <div class="sig-box"><div class="sig-label">توقيع المحاسب</div><div class="sig-line"></div></div>
      </div>
      <div class="foot-note">صدر هذا المستند إلكترونياً من ${esc(officeName || "منصة العدالة")} • ${esc(new Date().toLocaleString("ar-SA"))}</div>
    </div>`;

  const grand = (d.type === "tax_invoice" ? d.total : d.amount);
  const rows = `
    <tr><td>المبلغ الأساسي</td><td class="num">${esc(d.amount.toLocaleString("ar-SA"))} ر.س</td></tr>
    ${d.type === "tax_invoice" ? `<tr><td>ضريبة القيمة المضافة (15%)</td><td class="num">${esc(d.tax.toLocaleString("ar-SA"))} ر.س</td></tr>` : ""}
    <tr class="total"><td>الإجمالي المستحق</td><td class="num">${esc(grand.toLocaleString("ar-SA"))} ر.س</td></tr>`;

  return `<!DOCTYPE html><html dir="rtl" lang="ar"${hc ? ' data-hc="1"' : ""}><head><meta charset="utf-8"><title>${esc(title)} #${esc(d.number)}</title>
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap" rel="stylesheet">
<style>
  :root{--navy:#0f1e4b;--navy-2:#1a3a8e;--gold:#c9961a;--gold-2:#8a6510;--ink:#0a0f1d;--muted:#4a5170;--paper:#ffffff;--soft:#f7f4ea;--rule:#e7e3d2}
  html[data-hc="1"]{--navy:#000814;--navy-2:#001233;--ink:#000000;--muted:#1e2233;--gold-2:#5a3f00;--rule:#9aa1b8}
  *{box-sizing:border-box}
  html,body{margin:0;background:#eef0f5;color:var(--ink);font-family:'Cairo',Tahoma,Arial,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .sheet{max-width:820px;margin:24px auto;background:var(--paper);padding:46px 52px 36px;border-radius:18px;box-shadow:0 30px 80px -40px rgba(15,30,75,.35);position:relative;overflow:hidden}
  /* Use a layout table so the letterhead (thead) and signature/footer (tfoot)
     are repeated automatically by the browser on every printed page. */
  table.page{width:100%;border-collapse:collapse}
  table.page thead{display:table-header-group}
  table.page tfoot{display:table-footer-group}
  table.page > thead > tr > td,
  table.page > tbody > tr > td,
  table.page > tfoot > tr > td{padding:0}
  .sheet::before{content:"";position:absolute;inset:0;background:radial-gradient(900px 200px at 100% 0%,rgba(201,150,26,.10),transparent 60%),radial-gradient(700px 220px at 0% 100%,rgba(15,30,75,.07),transparent 60%);pointer-events:none}
  html[data-hc="1"] .sheet::before{display:none}
  .watermark{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none;opacity:.045}
  html[data-hc="1"] .watermark{display:none}
  .watermark span{font-size:140px;font-weight:900;color:var(--navy);transform:rotate(-22deg);letter-spacing:6px}
  .letterhead{position:relative}
  .lh-top{display:flex;align-items:center;gap:18px}
  .lh-info{flex:1;min-width:0}
  .lh-name{font-size:24px;font-weight:900;color:var(--navy);letter-spacing:.2px;line-height:1.2}
  .lh-name-en{font-size:12px;color:#3a4060;direction:ltr;text-align:left;font-weight:700;margin-top:2px}
  .lh-line{font-size:12px;color:#2c3247;margin-top:4px;font-weight:600}
  .lh-meta{font-size:11px;color:#414867;margin-top:6px;line-height:1.7;font-weight:600}
  .lh-badge{text-align:center;background:linear-gradient(160deg,var(--navy),#152965);color:#fff;border-radius:14px;padding:12px 16px;min-width:130px;box-shadow:0 12px 28px -14px rgba(15,30,75,.55);border:1px solid rgba(201,150,26,.45)}
  .lh-badge-label{font-size:11px;font-weight:700;color:#e6c861;letter-spacing:.4px}
  .lh-badge-num{font-size:18px;font-weight:900;margin-top:2px;direction:ltr}
  .lh-rule{display:flex;gap:4px;margin-top:14px;height:6px;border-radius:999px;overflow:hidden}
  .lh-rule span:nth-child(1){flex:6;background:linear-gradient(90deg,var(--gold-2),var(--gold))}
  .lh-rule span:nth-child(2){flex:1;background:var(--navy)}
  .lh-rule span:nth-child(3){flex:3;background:linear-gradient(90deg,var(--gold),transparent)}
  h1.doc-title{margin:22px 0 6px;font-size:22px;color:var(--navy);font-weight:900;letter-spacing:.3px}
  .doc-sub{color:var(--muted);font-size:12px;font-weight:600;margin-bottom:18px}
  .meta-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:14px 0 18px}
  .meta-cell{background:var(--soft);border:1px solid #efe6c8;border-radius:12px;padding:10px 14px}
  .meta-cell .k{font-size:10.5px;color:var(--muted);font-weight:700;margin-bottom:2px}
  .meta-cell .v{font-size:13.5px;color:var(--ink);font-weight:800}
  .desc-box{background:#fbfaf3;border-right:4px solid var(--gold);border-radius:10px;padding:12px 14px;margin:6px 0 18px;font-size:13px;color:#191c2a;font-weight:600;line-height:1.7}
  table.amounts{width:100%;border-collapse:separate;border-spacing:0;margin-top:8px;border:1px solid var(--rule);border-radius:14px;overflow:hidden;box-shadow:0 8px 24px -16px rgba(15,30,75,.25)}
  table.amounts td{padding:13px 16px;font-size:13.5px;color:var(--ink);font-weight:700;background:#fff;border-bottom:1px solid var(--rule)}
  table.amounts td.num{text-align:left;direction:ltr;font-variant-numeric:tabular-nums}
  table.amounts tr:last-child td{border-bottom:none}
  table.amounts tr.total td{background:linear-gradient(90deg,var(--navy),#1a3a8e);color:#fff;font-weight:900;font-size:15px}
  html[data-hc="1"] table.amounts tr.total td{background:var(--navy)}
  table.amounts tr.total td.num{color:#ffe69a}
  html[data-hc="1"] table.amounts tr.total td.num{color:#ffffff}
  .doc-footer{margin-top:30px}
  .foot-line{display:flex;gap:3px;height:4px;border-radius:999px;overflow:hidden;margin-bottom:14px}
  .foot-line span:nth-child(1){flex:3;background:linear-gradient(90deg,transparent,var(--gold))}
  .foot-line span:nth-child(2){flex:1;background:var(--navy)}
  .foot-line span:nth-child(3){flex:6;background:linear-gradient(90deg,var(--gold),var(--gold-2))}
  .foot-html{font-size:11px;color:#3a4060;text-align:center;margin-bottom:14px;font-weight:600}
  .foot-sig{display:grid;grid-template-columns:1fr auto 1fr;gap:24px;align-items:end;margin-top:12px}
  .sig-box .sig-label{font-size:11px;color:var(--muted);font-weight:700;margin-bottom:30px}
  .sig-box .sig-line{border-top:1.5px dashed #b9a974}
  .sig-stamp{width:96px;height:96px;border-radius:50%;border:2px dashed var(--gold);display:grid;place-items:center;color:var(--gold-2);font-weight:800;font-size:12px;text-align:center}
  .foot-note{margin-top:14px;text-align:center;font-size:10.5px;color:var(--muted);font-weight:600}
  @page{size:A4;margin:14mm 14mm 16mm 14mm}
  @media print{
    html,body{background:#fff}
    .sheet{box-shadow:none;border-radius:0;margin:0;padding:0;max-width:none}
    .sheet::before{display:none}
    table.page{page-break-inside:auto}
    table.page tr{page-break-inside:avoid;page-break-after:auto}
    table.amounts{page-break-inside:avoid}
    .foot-sig{page-break-inside:avoid}
    .letterhead{padding-bottom:6px}
    .doc-footer{padding-top:6px}
  }
</style></head>
<body>
  <div class="sheet">
    <div class="watermark"><span>${esc(officeName || "العدالة")}</span></div>
    <table class="page" role="presentation">
      <thead><tr><td>${letterhead}</td></tr></thead>
      <tfoot><tr><td>${footer}</td></tr></tfoot>
      <tbody><tr><td>
        <h1 class="doc-title">${esc(title)}</h1>
        <div class="doc-sub">تاريخ الإصدار: ${esc(new Date().toLocaleDateString("ar-SA"))} • رقم المستند: ${esc(d.number)}</div>
        <div class="meta-grid">
          <div class="meta-cell"><div class="k">العميل</div><div class="v">${esc(d.client) || "—"}</div></div>
          <div class="meta-cell"><div class="k">${d.type === "voucher" ? "صادر إلى" : "المُحرَّر باسم"}</div><div class="v">${esc(officeName) || "مكتب المحاماة"}</div></div>
          ${d.caseTitle ? `<div class="meta-cell" style="grid-column:1/-1"><div class="k">القضية المرتبطة</div><div class="v">${esc(d.caseTitle)}</div></div>` : ""}
        </div>
        ${d.desc ? `<div class="desc-box"><strong style="color:var(--navy)">البيان:</strong> ${esc(d.desc)}</div>` : ""}
        <table class="amounts">${rows}</table>
      </td></tr></tbody>
    </table>
  </div>
</body></html>`;
}
