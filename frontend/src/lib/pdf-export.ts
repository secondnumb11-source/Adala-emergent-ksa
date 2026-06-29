/**
 * Generate a luxurious A4 PDF from a record's key/value pairs.
 * Renders an off-screen DOM in Arabic RTL, then captures it via html2canvas
 * (which preserves Arabic shaping) and embeds as image in jsPDF.
 *
 * Reads the office identity (logo / name) from app-settings so every exported
 * document carries the firm's letterhead automatically.
 */
import { loadSettings } from "@/lib/app-settings";

function isSafeImgSrc(v: string): boolean {
  const s = v.trim();
  if (/^https?:\/\//i.test(s)) return true;
  return /^data:image\/(png|jpe?g|gif|webp|svg\+xml);base64,[A-Za-z0-9+/=]+$/i.test(s);
}

function officeHeader(): string {
  try {
    const o = loadSettings().office;
    const name = o.arabicName || o.officeName;
    if (!o.logoDataUrl && !name) return "";
    const safeLogo = o.logoDataUrl && isSafeImgSrc(o.logoDataUrl) ? o.logoDataUrl : "";
    return `
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px;padding-bottom:12px;border-bottom:1px dashed #d4af37;">
        ${safeLogo ? `<img src="${escape(safeLogo)}" style="height:56px;width:56px;object-fit:contain;border-radius:10px;border:1px solid #e6d8a5;background:#fff;padding:4px;" />` : ""}
        <div style="flex:1;text-align:right;">
          ${name ? `<div style="font-size:16px;font-weight:800;color:#0c1426;">${escape(name)}</div>` : ""}
          ${o.licenseText ? `<div style="font-size:10px;color:#5b6478;margin-top:2px;">${escape(o.licenseText)}</div>` : ""}
          ${o.phone || o.email ? `<div style="font-size:10px;color:#8b6b22;margin-top:2px;">${[o.phone, o.email].filter(Boolean).map(escape).join(" · ")}</div>` : ""}
        </div>
      </div>`;
  } catch { return ""; }
}

export type PdfField = { label: string; value: string | number | null | undefined };


export async function exportRecordPdf(opts: {
  title: string;
  subtitle?: string;
  fields: PdfField[];
  footer?: string;
  fileName?: string;
}) {
  const { default: html2canvas } = await import("html2canvas");
  const { default: jsPDF } = await import("jspdf");

  const wrap = document.createElement("div");
  wrap.dir = "rtl";
  wrap.style.cssText = [
    "position:fixed", "top:-99999px", "right:0", "width:794px",
    "padding:48px", "background:#fdfaf3", "font-family:Tajawal,system-ui,sans-serif",
    "color:#0c1426", "box-sizing:border-box",
  ].join(";");

  const rows = opts.fields
    .filter((f) => f.value !== null && f.value !== undefined && f.value !== "")
    .map((f) => `
      <tr>
        <th style="text-align:right;padding:12px 14px;background:#0c1426;color:#d4af37;width:38%;border:1px solid #d4af37;font-weight:800;font-size:13px;">${escape(f.label)}</th>
        <td style="text-align:right;padding:12px 14px;background:#fff;border:1px solid #e6d8a5;font-size:13px;">${escape(String(f.value))}</td>
      </tr>
    `).join("");

  wrap.innerHTML = `
    <div style="border:3px double #d4af37;padding:28px;border-radius:18px;background:linear-gradient(180deg,#fffdf6 0%,#fdfaf3 100%);">
      ${officeHeader()}
      <div style="display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:2px solid #d4af37;">
        <div>
          <div style="font-size:11px;letter-spacing:.3em;color:#8b6b22;font-weight:700;">منصة العدالة</div>
          <h1 style="margin:6px 0 0;font-size:24px;color:#0c1426;font-weight:800;">${escape(opts.title)}</h1>
          ${opts.subtitle ? `<div style="margin-top:4px;font-size:12px;color:#5b6478;">${escape(opts.subtitle)}</div>` : ""}
        </div>
        <div style="text-align:left;font-size:11px;color:#5b6478;">
          ${new Intl.DateTimeFormat("ar-SA-u-ca-gregory", { dateStyle: "long", timeStyle: "short" }).format(new Date())}
        </div>
      </div>
      <table style="width:100%;border-collapse:collapse;margin-top:18px;direction:rtl;">${rows}</table>
      ${opts.footer ? `<div style="margin-top:22px;padding:12px;border-top:1px dashed #d4af37;font-size:11px;color:#5b6478;">${escape(opts.footer)}</div>` : ""}
      <div style="margin-top:20px;text-align:center;font-size:10px;color:#8b6b22;letter-spacing:.2em;">— مستند رسمي صادر عن منصة العدالة —</div>
    </div>
  `;
  document.body.appendChild(wrap);

  try {
    await new Promise((r) => setTimeout(r, 50));
    const canvas = await html2canvas(wrap, { scale: 2, backgroundColor: "#fdfaf3", logging: false });
    const img = canvas.toDataURL("image/jpeg", 0.95);
    const pdf = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
    const pageW = pdf.internal.pageSize.getWidth();
    const pageH = pdf.internal.pageSize.getHeight();
    const ratio = canvas.width / pageW;
    const imgH = canvas.height / ratio;
    let y = 0;
    while (y < imgH) {
      if (y > 0) pdf.addPage();
      pdf.addImage(img, "JPEG", 0, -y, pageW, imgH);
      y += pageH;
    }
    pdf.save(opts.fileName || `${opts.title}-${new Date().toISOString().slice(0, 10)}.pdf`);
  } finally {
    document.body.removeChild(wrap);
  }
}

function escape(s: string) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]!));
}

/**
 * Render multiple records either:
 * - mode "combined": one PDF with each record on its own page
 * - mode "zip":      one PDF per record, all bundled in a zip
 */
export async function exportRecordsBundle(opts: {
  records: Array<{ title: string; subtitle?: string; fields: PdfField[]; footer?: string; fileName?: string }>;
  mode: "combined" | "zip";
  bundleName: string;
}) {
  const { records, mode, bundleName } = opts;
  if (records.length === 0) return;
  const { default: html2canvas } = await import("html2canvas");
  const { default: jsPDF } = await import("jspdf");

  const renderOne = async (rec: typeof records[number]): Promise<{ canvas: HTMLCanvasElement }> => {
    const wrap = document.createElement("div");
    wrap.dir = "rtl";
    wrap.style.cssText = [
      "position:fixed", "top:-99999px", "right:0", "width:794px",
      "padding:48px", "background:#fdfaf3", "font-family:Tajawal,system-ui,sans-serif",
      "color:#0c1426", "box-sizing:border-box",
    ].join(";");
    const rows = rec.fields
      .filter((f) => f.value !== null && f.value !== undefined && f.value !== "")
      .map((f) => `
        <tr>
          <th style="text-align:right;padding:12px 14px;background:#0c1426;color:#d4af37;width:38%;border:1px solid #d4af37;font-weight:800;font-size:13px;">${escape(f.label)}</th>
          <td style="text-align:right;padding:12px 14px;background:#fff;border:1px solid #e6d8a5;font-size:13px;">${escape(String(f.value))}</td>
        </tr>`).join("");
    wrap.innerHTML = `
      <div style="border:3px double #d4af37;padding:28px;border-radius:18px;background:#fffdf6;">
        ${officeHeader()}
        <div style="display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:2px solid #d4af37;">
          <div>
            <div style="font-size:11px;letter-spacing:.3em;color:#8b6b22;font-weight:700;">منصة العدالة</div>
            <h1 style="margin:6px 0 0;font-size:22px;color:#0c1426;font-weight:800;">${escape(rec.title)}</h1>
            ${rec.subtitle ? `<div style="margin-top:4px;font-size:12px;color:#5b6478;">${escape(rec.subtitle)}</div>` : ""}
          </div>
          <div style="text-align:left;font-size:11px;color:#5b6478;">
            ${new Intl.DateTimeFormat("ar-SA-u-ca-gregory", { dateStyle: "long", timeStyle: "short" }).format(new Date())}
          </div>
        </div>
        <table style="width:100%;border-collapse:collapse;margin-top:18px;direction:rtl;">${rows}</table>
        ${rec.footer ? `<div style="margin-top:22px;padding:12px;border-top:1px dashed #d4af37;font-size:11px;color:#5b6478;">${escape(rec.footer)}</div>` : ""}
      </div>`;
    document.body.appendChild(wrap);
    try {
      await new Promise((r) => setTimeout(r, 30));
      const canvas = await html2canvas(wrap, { scale: 2, backgroundColor: "#fdfaf3", logging: false });
      return { canvas };
    } finally {
      document.body.removeChild(wrap);
    }
  };

  if (mode === "combined") {
    const pdf = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
    const pageW = pdf.internal.pageSize.getWidth();
    const pageH = pdf.internal.pageSize.getHeight();
    for (let i = 0; i < records.length; i++) {
      const { canvas } = await renderOne(records[i]);
      const img = canvas.toDataURL("image/jpeg", 0.9);
      const ratio = canvas.width / pageW;
      const imgH = canvas.height / ratio;
      let y = 0;
      let first = true;
      while (y < imgH) {
        if (!first || i > 0) pdf.addPage();
        pdf.addImage(img, "JPEG", 0, -y, pageW, imgH);
        y += pageH;
        first = false;
      }
    }
    pdf.save(`${bundleName}.pdf`);
    return;
  }

  // zip mode
  const { default: JSZip } = await import("jszip");
  const zip = new JSZip();
  for (const rec of records) {
    const { canvas } = await renderOne(rec);
    const img = canvas.toDataURL("image/jpeg", 0.9);
    const pdf = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
    const pageW = pdf.internal.pageSize.getWidth();
    const pageH = pdf.internal.pageSize.getHeight();
    const ratio = canvas.width / pageW;
    const imgH = canvas.height / ratio;
    let y = 0;
    let first = true;
    while (y < imgH) {
      if (!first) pdf.addPage();
      pdf.addImage(img, "JPEG", 0, -y, pageW, imgH);
      y += pageH;
      first = false;
    }
    const blob = pdf.output("blob");
    zip.file(rec.fileName ?? `${rec.title}.pdf`, blob);
  }
  const zipBlob = await zip.generateAsync({ type: "blob" });
  const url = URL.createObjectURL(zipBlob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${bundleName}.zip`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
