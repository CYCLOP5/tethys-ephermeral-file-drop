import { Link, Outlet } from "react-router-dom";

export function App() {
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="brand">
          <span className="dot" /> Tethys
        </Link>
        <span className="tagline">Zero-Trust Ephemeral Secure File Drop</span>
      </header>
      <main className="main">
        <Outlet />
      </main>
      <footer className="footer">
        Files are AES-256-GCM encrypted in your browser. The server never sees
        plaintext or your passphrase.
      </footer>
    </div>
  );
}
