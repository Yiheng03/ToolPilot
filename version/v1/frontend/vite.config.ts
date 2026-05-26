import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

const rootDir = fileURLToPath(new URL(".", import.meta.url))

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(rootDir, "./src"),
      "next/link": path.resolve(rootDir, "./src/shims/next-link.tsx"),
      "next/dynamic": path.resolve(rootDir, "./src/shims/next-dynamic.tsx"),
    },
  },
})
