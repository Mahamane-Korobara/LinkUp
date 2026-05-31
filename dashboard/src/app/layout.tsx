import type { Metadata } from "next";
import Link from "next/link";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Linkup — Dashboard",
  description: "Appairage et gestion des téléphones Linkup connectés à ce PC.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="fr"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-slate-50">
        <header className="border-b border-slate-200 bg-white">
          <nav className="max-w-2xl mx-auto flex items-center gap-6 px-6 h-14">
            <Link href="/devices" className="font-bold text-indigo-600">
              🔗 Linkup
            </Link>
            <Link
              href="/pair"
              className="text-sm text-slate-600 hover:text-slate-900"
            >
              Appairer
            </Link>
            <Link
              href="/devices"
              className="text-sm text-slate-600 hover:text-slate-900"
            >
              Téléphones
            </Link>
            <Link
              href="/files"
              className="text-sm text-slate-600 hover:text-slate-900"
            >
              Fichiers
            </Link>
          </nav>
        </header>
        <div className="flex-1">{children}</div>
      </body>
    </html>
  );
}
