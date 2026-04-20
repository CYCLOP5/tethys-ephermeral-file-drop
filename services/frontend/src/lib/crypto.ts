// Client-side crypto helpers. Every byte the user picks is encrypted here
// before it leaves the browser. The passphrase never hits the network; the
// salt is part of the share URL fragment (so it's invisible to the server).

const PBKDF2_ITERATIONS = 300_000;
const KEY_LENGTH_BITS = 256;
const SALT_LENGTH_BYTES = 16;
const IV_LENGTH_BYTES = 12;

/** Derive a 256-bit AES-GCM key from a passphrase using PBKDF2-SHA-256. */
async function deriveKey(passphrase: string, salt: Uint8Array): Promise<CryptoKey> {
  const enc = new TextEncoder();
  const baseKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(passphrase),
    { name: "PBKDF2" },
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt,
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: KEY_LENGTH_BITS },
    false,
    ["encrypt", "decrypt"],
  );
}

export interface EncryptedBlob {
  /** ciphertext + GCM tag */
  ciphertext: Uint8Array;
  iv: Uint8Array;
  salt: Uint8Array;
}

export async function encryptFile(file: File, passphrase: string): Promise<EncryptedBlob> {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_LENGTH_BYTES));
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH_BYTES));
  const key = await deriveKey(passphrase, salt);

  const plaintext = new Uint8Array(await file.arrayBuffer());
  const buf = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);

  // Prepend a small header so the download side knows the original filename
  // and mime type without a separate metadata round-trip. Layout:
  //   [4B header-length][utf8 json metadata][ciphertext]
  const meta = new TextEncoder().encode(
    JSON.stringify({ n: file.name, t: file.type || "application/octet-stream" }),
  );
  const header = new Uint8Array(4);
  new DataView(header.buffer).setUint32(0, meta.length, false);

  const out = new Uint8Array(header.length + meta.length + buf.byteLength);
  out.set(header, 0);
  out.set(meta, header.length);
  out.set(new Uint8Array(buf), header.length + meta.length);

  return { ciphertext: out, iv, salt };
}

export interface DecryptedFile {
  bytes: Uint8Array;
  filename: string;
  mimeType: string;
}

export async function decryptBlob(
  ciphertext: Uint8Array,
  iv: Uint8Array,
  salt: Uint8Array,
  passphrase: string,
): Promise<DecryptedFile> {
  const key = await deriveKey(passphrase, salt);

  const headerLen = new DataView(ciphertext.buffer, ciphertext.byteOffset, 4).getUint32(0, false);
  if (headerLen <= 0 || headerLen > 4096) {
    throw new Error("corrupt header");
  }
  const metaBytes = ciphertext.slice(4, 4 + headerLen);
  const body = ciphertext.slice(4 + headerLen);

  const { n: filename, t: mimeType } = JSON.parse(new TextDecoder().decode(metaBytes));
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, body);

  return {
    bytes: new Uint8Array(plain),
    filename,
    mimeType,
  };
}

/** base64url without padding. */
export function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromB64url(s: string): Uint8Array {
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  const b64 = (s + pad).replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
