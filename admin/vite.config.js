import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "/",
  plugins: [react()],
  server: {
    port: 5173,
    open: true,
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom", "react-router-dom"],
          firebase: ["firebase/app", "firebase/auth", "firebase/firestore", "firebase/storage"],
          maps: ["@react-google-maps/api"],
          pdf: ["jspdf"],
          mui: ["@mui/material", "@mui/icons-material", "@emotion/react", "@emotion/styled"],
        },
      },
    },
    chunkSizeWarningLimit: 900,
  },
});
