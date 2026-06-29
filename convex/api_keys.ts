import { mutation, query, internalQuery } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

function simpleHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, "0");
}

function generateApiKey(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let key = "adala_";
  for (let i = 0; i < 32; i++) key += chars.charAt(Math.floor(Math.random() * chars.length));
  return key;
}

export const createApiKey = mutation({
  args: { label: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const user = await ctx.db.query("users").withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier)).unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
    const rawKey = generateApiKey();
    const keyHash = simpleHash(rawKey);
    const keyPrefix = rawKey.substring(0, 12);
    await ctx.db.insert("api_keys", { userId: user._id, keyHash, keyPrefix, label: args.label ?? "مفتاح ناجز", isActive: true });
    return { key: rawKey, prefix: keyPrefix };
  },
});

export const listApiKeys = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];
    const user = await ctx.db.query("users").withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier)).unique();
    if (!user) return [];
    return await ctx.db.query("api_keys").withIndex("by_user", (q) => q.eq("userId", user._id)).collect();
  },
});

export const revokeApiKey = mutation({
  args: { keyId: v.id("api_keys") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const user = await ctx.db.query("users").withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier)).unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
    const key = await ctx.db.get(args.keyId);
    if (!key || key.userId !== user._id) throw new ConvexError({ message: "Key not found", code: "NOT_FOUND" });
    await ctx.db.patch(args.keyId, { isActive: false });
    return true;
  },
});

export const validateApiKey = query({
  args: { keyHash: v.string() },
  handler: async (ctx, args): Promise<{ userId: string; valid: boolean } | null> => {
    const key = await ctx.db.query("api_keys").withIndex("by_hash", (q) => q.eq("keyHash", args.keyHash)).unique();
    if (!key || !key.isActive) return null;
    return { userId: key.userId, valid: true };
  },
});

export const getUserIdFromKeyHash = internalQuery({
  args: { keyHash: v.string() },
  handler: async (ctx, args) => {
    const key = await ctx.db.query("api_keys").withIndex("by_hash", (q) => q.eq("keyHash", args.keyHash)).unique();
    if (!key || !key.isActive) return null;
    return key.userId;
  },
});