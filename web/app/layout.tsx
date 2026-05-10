import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Marginalia",
  description: "Riscopri i tuoi highlight Kindle",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="it">
      <body className="bg-bg text-text antialiased">{children}</body>
    </html>
  );
}
