import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { language } from "./i18n";
import "./generated/colors.css";
import "./styles.css";

document.documentElement.lang = language();

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
