import { useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { decryptBlob, fromB64url } from "../lib/crypto";
import { fetchDownload, getPresigned } from "../lib/api";

type Phase = "idle" | "fetching" | "decrypting" | "done";

export function DownloadPage() {
  const { token = "" } = useParams();
  const [passphrase, setPassphrase] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const [salt, iv] = useMemo(() => {
    const frag = window.location.hash.replace(/^#/, "");
    const parts = frag.split(".");
    if (parts.length !== 2) return [null, null] as const;
    try {
      return [fromB64url(parts[0]), fromB64url(parts[1])] as const;
    } catch {
      return [null, null] as const;
    }
  }, []);

  const fragmentOk = !!salt && !!iv;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!fragmentOk) {
      setError("Share URL is missing the salt/iv fragment.");
      return;
    }
    setError(null);
    try {
      setPhase("fetching");
      setProgress(0);
      const info = await fetchDownload(token);
      const ciphertext = await getPresigned(info.presigned_get_url, setProgress);

      setPhase("decrypting");
      const { bytes, filename, mimeType } = await decryptBlob(ciphertext, iv!, salt!, passphrase);

      const blob = new Blob([bytes as any], { type: mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename || "download.bin";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      setPhase("done");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setPhase("idle");
    }
  }

  return (
    <form className="card" onSubmit={handleSubmit}>
      <h1>Decrypt a file</h1>
      <p className="muted">
        Enter the passphrase shared with you out of band. Decryption happens
        entirely in your browser.
      </p>

      {!fragmentOk && (
        <div className="error">
          This link is missing the salt/iv fragment. It may have been truncated
          when shared.
        </div>
      )}

      <label>
        Passphrase
        <input
          type="password"
          autoComplete="current-password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          required
          disabled={phase !== "idle" || !fragmentOk}
        />
      </label>

      <button
        className="button-primary"
        type="submit"
        disabled={phase !== "idle" || !passphrase || !fragmentOk}
      >
        {phase === "idle" && "Download and decrypt"}
        {phase === "fetching" && `Fetching... ${Math.round(progress * 100)}%`}
        {phase === "decrypting" && "Decrypting..."}
        {phase === "done" && "Done"}
      </button>

      {phase === "fetching" && (
        <div className="progress">
          <div style={{ width: `${Math.round(progress * 100)}%` }} />
        </div>
      )}

      {error && <div className="error">{error}</div>}
    </form>
  );
}
