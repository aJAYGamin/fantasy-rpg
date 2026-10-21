import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/500-italic.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/cinzel/600.css";
import "@fontsource/cinzel/700.css";
import "./theme/tokens.css";
import "./theme/colorThemes.css";
import "./theme/global.css";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";

const root = document.getElementById("root");
if (!root) throw new Error("index.html has no #root element");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
