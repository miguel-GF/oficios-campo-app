import type { ReactNode } from "react";

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html lang="es">
      <body style={{ margin: 0, fontFamily: "system-ui", background: "#f5f4ef" }}>
        {children}
      </body>
    </html>
  );
}
