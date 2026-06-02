import { Plus_Jakarta_Sans } from "next/font/google";
import "./globals.css";

const jakarta = Plus_Jakarta_Sans({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata = {
  metadataBase: new URL("https://linkup.sahelstack.tech"),
  title: "Linkup — Ton téléphone et ton PC, reliés en un scan",
  description:
    "Transfère fichiers, photos, liens et presse-papier entre ton téléphone et ton PC, sans câble et sans compte. Une seule app, reliée en scannant un QR code. Tes données restent sur ton réseau.",
  keywords: [
    "transfert fichier téléphone PC",
    "sans câble",
    "presse-papier partagé",
    "webcam téléphone",
    "Linkup",
  ],
  openGraph: {
    title: "Linkup — Ton téléphone et ton PC, reliés en un scan",
    description:
      "Fichiers, photos, liens, presse-papier, caméra… entre ton tel et ton PC. Sans câble, sans compte, sans cloud.",
    type: "website",
    locale: "fr_FR",
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="fr" className={jakarta.variable}>
      <body>{children}</body>
    </html>
  );
}
