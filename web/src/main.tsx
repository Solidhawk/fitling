import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { language } from "./i18n";
import { ErrorBoundary } from "./ui/ErrorBoundary";
import "./generated/colors.css";
import "./styles.css";

document.documentElement.lang = language();

// The app on the home screen opens without a connection (phase 7). Not in the dev server, where every change must show.
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, { scope: import.meta.env.BASE_URL }).catch(() => undefined);
}
// The app puts each screen at its place itself (scrollPerDepth.ts): the browser would also restore the place of an entry
// it passes on its way back, one that leads nowhere (historyStack.ts) or the welcome screen's (UNFORGET S40).
if ("scrollRestoration" in history) history.scrollRestoration = "manual";
// On the home screen the browser keeps what the app stores (photos, what waits to be sent) when space runs low.
const standalone = matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone === true;
if (standalone) navigator.storage?.persist?.().catch(() => false);

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </StrictMode>,
  );
}
