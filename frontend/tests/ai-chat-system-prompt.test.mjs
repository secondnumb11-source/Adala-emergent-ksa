// Regression: POST /api/ai-chat MUST ignore any client-sent `system` field
// and always apply the server-defined SYSTEM_PROMPT.
//
// The server source is the single source of truth: it never reads
// `body.system`, so a client trying to override the prompt has no effect.
// This test asserts that property statically (the only way to cover it
// without invoking the live AI gateway).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(
  resolve(here, "..", "src", "routes", "api", "ai-chat.ts"),
  "utf8",
);

// 1. The handler must NOT destructure or read `system` from the request body.
assert.ok(
  !/body\.\s*system\b/.test(source),
  "ai-chat handler must not read `system` from the request body",
);
assert.ok(
  !/\{\s*[^}]*\bsystem\b[^}]*\}\s*=\s*(await\s+)?request\.json/.test(source),
  "ai-chat handler must not destructure `system` out of the request body",
);

// 2. streamText must be called with the server-defined SYSTEM_PROMPT.
assert.ok(
  /system:\s*SYSTEM_PROMPT\b/.test(source),
  "ai-chat handler must pass the server-defined SYSTEM_PROMPT to streamText",
);

// 3. SYSTEM_PROMPT must be a server-side constant (declared in the module).
assert.ok(
  /const\s+SYSTEM_PROMPT\s*=/.test(source),
  "SYSTEM_PROMPT must be declared as a server-side constant",
);

console.log("ai-chat-system-prompt: OK — client `system` is ignored, server SYSTEM_PROMPT enforced");