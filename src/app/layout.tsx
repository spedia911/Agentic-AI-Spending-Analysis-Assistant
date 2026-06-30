import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Spending Analysis Assistant",
  description: "Drive-first agentic spending analysis dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
