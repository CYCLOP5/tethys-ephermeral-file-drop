import { describe, it, expect } from "vitest";
import { encryptFile, decryptBlob, b64url, fromB64url } from "./crypto";

describe("crypto", () => {
  it("round-trips", async () => {
    const data = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
    const file = new File([data], "secret.bin", { type: "application/octet-stream" });
    const enc = await encryptFile(file, "correct horse battery staple");
    const dec = await decryptBlob(enc.ciphertext, enc.iv, enc.salt, "correct horse battery staple");
    expect(Array.from(dec.bytes)).toEqual(Array.from(data));
    expect(dec.filename).toBe("secret.bin");
    expect(dec.mimeType).toBe("application/octet-stream");
  });

  it("rejects wrong passphrase", async () => {
    const file = new File([new Uint8Array([9, 8, 7])], "x.bin");
    const enc = await encryptFile(file, "good");
    await expect(decryptBlob(enc.ciphertext, enc.iv, enc.salt, "bad")).rejects.toBeDefined();
  });

  it("base64url round-trip", () => {
    const bytes = new Uint8Array([255, 0, 127, 128, 1]);
    expect(Array.from(fromB64url(b64url(bytes)))).toEqual(Array.from(bytes));
  });
});
