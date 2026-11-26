import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// Published at https://solidhawk.github.io/fitling/ (D-24).
export default defineConfig({
  base: "/fitling/",
  plugins: [react()],
  test: {
    include: ["src/**/*.test.ts", "scripts/**/*.test.mjs"],
  },
});
