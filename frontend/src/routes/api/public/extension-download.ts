import { createFileRoute } from "@tanstack/react-router";
import JSZip from "jszip";

// Bundle the extension source files at build time as raw strings/binaries so the
// download endpoint works on every deployment target (Node / Cloudflare /
// Vercel / preview) without depending on the runtime `public/` directory.
import manifest from "../../../../extension/manifest.json?raw";
import backgroundJs from "../../../../extension/background.js?raw";
import contentJs from "../../../../extension/content.js?raw";
import contentCss from "../../../../extension/content.css?raw";
import popupHtml from "../../../../extension/popup.html?raw";
import popupJs from "../../../../extension/popup.js?raw";
import popupCss from "../../../../extension/popup.css?raw";
import optionsHtml from "../../../../extension/options.html?raw";
import optionsJs from "../../../../extension/options.js?raw";
import injectedJs from "../../../../extension/injected.js?raw";
// Vite's `?inline` returns the file as a base64 data URL string — perfect for binary assets.
import iconPng from "../../../../extension/icon.png?inline";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function dataUrlToUint8(dataUrl: string): Uint8Array {
  const idx = dataUrl.indexOf(",");
  const b64 = idx >= 0 ? dataUrl.slice(idx + 1) : dataUrl;
  // Works in both Node and edge runtimes
  if (typeof Buffer !== "undefined") return new Uint8Array(Buffer.from(b64, "base64"));
  const bin = atob(b64);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return arr;
}

async function buildZip(): Promise<Uint8Array> {
  const zip = new JSZip();
  zip.file("manifest.json", manifest);
  zip.file("background.js", backgroundJs);
  zip.file("content.js", contentJs);
  zip.file("content.css", contentCss);
  zip.file("popup.html", popupHtml);
  zip.file("popup.js", popupJs);
  zip.file("popup.css", popupCss);
  zip.file("options.html", optionsHtml);
  zip.file("options.js", optionsJs);
  zip.file("injected.js", injectedJs);
  const iconData = dataUrlToUint8(iconPng);
  zip.file("icons/icon16.png", iconData);
  zip.file("icons/icon48.png", iconData);
  zip.file("icons/icon128.png", iconData);
  return zip.generateAsync({ type: "uint8array", compression: "DEFLATE", compressionOptions: { level: 6 } });
}

export const Route = createFileRoute("/api/public/extension-download")({
  server: {
    handlers: {
      OPTIONS: () => new Response(null, { status: 204, headers: CORS }),
      GET: async () => {
        try {
          const data = await buildZip();
          return new Response(data as unknown as BodyInit, {
            status: 200,
            headers: {
              ...CORS,
              "Content-Type": "application/zip",
              "Content-Disposition": 'attachment; filename="adala-najiz-extension-v3.zip"',
              "Content-Length": String(data.byteLength),
              "Cache-Control": "no-store",
            },
          });
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          return new Response(JSON.stringify({ ok: false, error: msg }), {
            status: 500,
            headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
          });
        }
      },
    },
  },
});
