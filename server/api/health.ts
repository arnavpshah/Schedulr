import type { VercelRequest, VercelResponse } from "@vercel/node";

export default function handler(
  _req: VercelRequest,
  res: VercelResponse,
): void {
  res.status(200).json({
    ok: true,
    service: "schedulr-server",
    version: "0.1.0",
    requiresApiKey: Boolean(process.env.SCHEDULR_API_KEY),
  });
}
