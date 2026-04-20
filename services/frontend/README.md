# Tethys Frontend

React + Vite + TypeScript. All crypto happens in the browser via the
WebCrypto API. The Vault server and S3 only ever see ciphertext.

## Layout

- `src/lib/crypto.ts` - AES-GCM / PBKDF2 helpers
- `src/lib/api.ts`    - Vault + S3 presigned URL client
- `src/pages/Upload.tsx`   - encrypt + upload flow
- `src/pages/Download.tsx` - download + decrypt flow

## Dev

```bash
npm install
VITE_API_BASE_URL=http://localhost:8080 npm run dev
```

## Build

```bash
npm run build        # -> dist/
npm run test         # vitest (requires Node 20+ with WebCrypto)
```

## Share URL format

```
https://<host>/d/<download_token>#<salt-b64url>.<iv-b64url>
```

The fragment after `#` never leaves the browser, so the salt and IV are
invisible to the server and to any proxy/CDN in between.
