import type { VercelRequest, VercelResponse } from "@vercel/node";

export function requireApiKey(
  req: VercelRequest,
  res: VercelResponse,
): boolean {
  const expected = process.env.SCHEDULR_API_KEY;
  if (!expected) {
    if (process.env.NODE_ENV === "production") {
      res.status(503).json({ error: "server_misconfigured" });
      return false;
    }
    return true;
  }
  const header = req.headers["x-api-key"];
  const provided = Array.isArray(header) ? header[0] : header;
  if (!provided || !timingSafeEqual(provided, expected)) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
  return true;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
