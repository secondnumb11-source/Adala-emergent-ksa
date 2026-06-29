/**
 * Error reporting utility.
 * Previously used Lovable error reporting; now a safe no-op stub.
 * Can be replaced with Sentry, LogRocket, or any error tracking service.
 */

type ErrorOptions = {
  mechanism?: "manual" | "onerror" | "unhandledrejection" | "react_error_boundary";
  handled?: boolean;
  severity?: "error" | "warning" | "info";
};

export function reportLovableError(error: unknown, context: Record<string, unknown> = {}, options?: ErrorOptions) {
  // Log to console in development; in production, replace with your error tracking service
  if (process.env.NODE_ENV === "development") {
    console.error("[Error]", error, context);
  }
}
