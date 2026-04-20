import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { App } from "./App";
import { UploadPage } from "./pages/Upload";
import { DownloadPage } from "./pages/Download";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route element={<App />}>
          <Route index element={<Navigate to="/upload" replace />} />
          <Route path="/upload" element={<UploadPage />} />
          <Route path="/d/:token" element={<DownloadPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
