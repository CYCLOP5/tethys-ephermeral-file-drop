const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "";
// A real deployment would issue short-lived JWTs per-session via SSO. For the
// demo we ship a single shared dev token compiled into the build; swap it for
// a real auth flow before shipping.
const UPLOAD_BEARER = import.meta.env.VITE_UPLOAD_BEARER ?? "";

export interface UploadInit {
  upload_id: string;
  presigned_put_url: string;
  download_token: string;
  expires_at: string;
}

export async function initUpload(sizeBytes: number, ttlSeconds: number, maxDownloads: number): Promise<UploadInit> {
  const resp = await fetch(`${API_BASE}/api/v1/uploads`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(UPLOAD_BEARER ? { Authorization: `Bearer ${UPLOAD_BEARER}` } : {}),
    },
    body: JSON.stringify({
      size_bytes: sizeBytes,
      ttl_seconds: ttlSeconds,
      max_downloads: maxDownloads,
    }),
  });
  if (!resp.ok) {
    throw new Error(`upload init failed: ${resp.status} ${await resp.text()}`);
  }
  return resp.json();
}

export async function putPresigned(url: string, bytes: Uint8Array, onProgress?: (pct: number) => void): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", url);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
    };
    xhr.onload = () => (xhr.status >= 200 && xhr.status < 300 ? resolve() : reject(new Error(`S3 PUT ${xhr.status}`)));
    xhr.onerror = () => reject(new Error("S3 PUT network error"));
    xhr.send(new Blob([bytes as any]));
  });
}

export interface DownloadInfo {
  presigned_get_url: string;
  expires_at: string;
  remaining_uses: number;
}

export async function fetchDownload(token: string): Promise<DownloadInfo> {
  const resp = await fetch(`${API_BASE}/api/v1/downloads/${encodeURIComponent(token)}`);
  if (resp.status === 410) throw new Error("This link has expired or been used up.");
  if (!resp.ok) throw new Error(`download lookup failed: ${resp.status}`);
  return resp.json();
}

export async function getPresigned(url: string, onProgress?: (pct: number) => void): Promise<Uint8Array> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url);
    xhr.responseType = "arraybuffer";
    xhr.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve(new Uint8Array(xhr.response));
      else reject(new Error(`S3 GET ${xhr.status}`));
    };
    xhr.onerror = () => reject(new Error("S3 GET network error"));
    xhr.send();
  });
}
