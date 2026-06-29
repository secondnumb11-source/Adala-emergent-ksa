import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createOpenAI } from "@ai-sdk/openai";

/**
 * AI provider factory for Gemini and OpenAI.
 * Replaces the previous Lovable AI gateway with direct provider access.
 */

let _googleProvider: ReturnType<typeof createGoogleGenerativeAI> | undefined;
let _openaiProvider: ReturnType<typeof createOpenAI> | undefined;

function getGoogleProvider() {
  if (!_googleProvider) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error("Missing GEMINI_API_KEY environment variable");
    _googleProvider = createGoogleGenerativeAI({ apiKey });
  }
  return _googleProvider;
}

function getOpenAIProvider() {
  if (!_openaiProvider) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error("Missing OPENAI_API_KEY environment variable");
    _openaiProvider = createOpenAI({ apiKey });
  }
  return _openaiProvider;
}

/**
 * Get a model by identifier string.
 * Supported prefixes:
 *   - "gemini:" or "google/" -> Gemini model (e.g., "gemini:gemini-2.0-flash" or "google/gemini-2.0-flash")
 *   - "openai:" or "gpt-" -> OpenAI model (e.g., "openai:gpt-4o-mini" or "gpt-4o-mini")
 * Default model: Gemini 2.0 Flash
 */
export function getModel(identifier?: string) {
  const id = identifier || "gemini:gemini-2.0-flash";

  // Gemini models
  if (id.startsWith("gemini:") || id.startsWith("google/")) {
    const modelName = id.replace(/^(gemini:|google\/)/, "");
    return getGoogleProvider()(modelName || "gemini-2.0-flash");
  }

  // OpenAI models
  if (id.startsWith("openai:") || id.startsWith("gpt-")) {
    const modelName = id.replace(/^(openai:)/, "");
    return getOpenAIProvider()(modelName || "gpt-4o-mini");
  }

  // Default: Gemini
  return getGoogleProvider()(id);
}

/** Get the default model for AI chat (Gemini Flash) */
export function getDefaultChatModel() {
  return getGoogleProvider()("gemini-2.0-flash");
}

/** Get an OpenAI model for fallback or alternative use */
export function getOpenAIModel(modelName = "gpt-4o-mini") {
  return getOpenAIProvider()(modelName);
}
