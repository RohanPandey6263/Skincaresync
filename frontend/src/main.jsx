import React from "react";
import { createRoot } from "react-dom/client";
import { Routes } from "./Routes.jsx";
import { AuthProvider } from "./context/AuthContext.jsx";
import { RouterProvider } from "./lib/router.jsx";
import { ToastProvider } from "./components/ui/Toaster.jsx";
import "./styles/index.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <RouterProvider>
      <ToastProvider>
        <AuthProvider>
          <Routes />
        </AuthProvider>
      </ToastProvider>
    </RouterProvider>
  </React.StrictMode>,
);
