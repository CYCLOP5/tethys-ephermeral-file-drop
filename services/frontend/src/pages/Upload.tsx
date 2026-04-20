import { useState } from "react";
import { encryptFile, b64url } from "../lib/crypto";
import { initUpload, putPresigned } from "../lib/api";

type Phase = "idle" | "encrypting" | "uploading" | "done";

export function UploadPage() {
  const [file, setFile] = useState<File | null>(null);
  const [passphrase, setPassphrase] = useState("");
  const [ttlMinutes, setTtlMinutes] = useState(60);
  const [maxDownloads, setMaxDownloads] = useState(1);
  const [phase, setPhase] = useState<Phase>("idle");
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [shareUrl, setShareUrl] = useState<string | null>(null);

  const canSubmit =
    phase === "idle" && !!file && passphrase.length >= 12 && ttlMinutes > 0 && maxDownloads > 0;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!file) return;
    setError(null);
    setShareUrl(null);
    try {
      setPhase("encrypting");
      setProgress(0);
      const { ciphertext, iv, salt } = await encryptFile(file, passphrase);

      setPhase("uploading");
      const init = await initUpload(ciphertext.byteLength, ttlMinutes * 60, maxDownloads);
      await putPresigned(init.presigned_put_url, ciphertext, setProgress);

      const fragment = [b64url(salt), b64url(iv)].join(".");
      const url = `${window.location.origin}/d/${init.download_token}#${fragment}`;
      setShareUrl(url);
      setPhase("done");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setPhase("idle");
    }
  }

  return (
    <form className="card" onSubmit={handleSubmit}>
      <h1>Upload a file</h1>
      <p className="muted">
        The file is encrypted in your browser with AES-256-GCM and a key
        derived from your passphrase. The server only sees ciphertext.
      </p>

      <label>
        File
        <input
          type="file"
          required
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          disabled={phase !== "idle"}
        />
      </label>

      <label>
        Passphrase (12+ characters - share out of band)
        <input
          type="password"
          autoComplete="new-password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          minLength={12}
          required
          disabled={phase !== "idle"}
        />
      </label>

      <div className="row">
        <label>
          TTL (minutes)
          <input
            type="number"
            min={1}
            max={10080}
            value={ttlMinutes}
            onChange={(e) => setTtlMinutes(Number(e.target.value))}
            disabled={phase !== "idle"}
          />
        </label>
        <label>
          Max downloads
          <input
            type="number"
            min={1}
            max={100}
            value={maxDownloads}
            onChange={(e) => setMaxDownloads(Number(e.target.value))}
            disabled={phase !== "idle"}
          />
        </label>
      </div>

      <button className="button-primary" type="submit" disabled={!canSubmit}>
        {phase === "idle" && "Encrypt and upload"}
        {phase === "encrypting" && "Encrypting..."}
        {phase === "uploading" && `Uploading... ${Math.round(progress * 100)}%`}
        {phase === "done" && "Done"}
      </button>

      {phase === "uploading" && (
        <div className="progress">
          <div style={{ width: `${Math.round(progress * 100)}%` }} />
        </div>
      )}

      {error && <div className="error">{error}</div>}

      {shareUrl && (
        <>
          <label>Share link (the passphrase is NOT in the URL)</label>
          <div className="share">{shareUrl}</div>
        </>
      )}
    </form>
  );
}
