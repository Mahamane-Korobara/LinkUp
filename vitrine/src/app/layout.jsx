import { Geist } from "next/font/google";
import "./globals.css";
import { FAQ } from "@/lib/faq";

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist",
  display: "swap",
});

const SITE_URL = "https://linkup-landing.sahelstack.tech";
const TITLE = "Linkup — Ton téléphone et ton PC, reliés en un scan";
// Meta description : ~155 caractères (au-delà, Google tronque), mots-clés en tête.
const DESCRIPTION =
  "Transfère fichiers, photos et presse-papier entre téléphone et PC, sans câble ni compte. L'alternative AirDrop pour Android et Linux, sur ton wifi. Gratuit.";
// Description plus riche réservée aux données structurées (pas de limite SERP).
const LONG_DESCRIPTION =
  "Linkup relie ton téléphone et ton PC sur le même wifi pour transférer fichiers, photos, vidéos et presse-papier, sans câble, sans compte et sans cloud. L'alternative AirDrop pour Android et Linux (Windows bientôt). Gratuit et open source.";

export const metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: TITLE,
    template: "%s · Linkup",
  },
  description: DESCRIPTION,
  applicationName: "Linkup",
  authors: [{ name: "Mahamane Korobara" }],
  creator: "Mahamane Korobara",
  keywords: [
    "transfert de fichiers téléphone PC",
    "envoyer photos téléphone vers PC sans câble",
    "presse-papier partagé téléphone PC",
    "alternative AirDrop pour Android et Linux",
    "partage local sans cloud ni compte",
    "appairage QR code",
    "Linkup",
  ],
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Linkup",
    title: TITLE,
    description:
      "Fichiers, photos et presse-papier entre ton tél et ton PC. Sans câble, sans compte, sans cloud. Gratuit, open source.",
    locale: "fr_FR",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Linkup — relie ton téléphone et ton PC en scannant un QR code",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description:
      "Fichiers, photos et presse-papier entre ton tél et ton PC. Sans câble, sans compte, sans cloud.",
    images: ["/og.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  verification: {
    google: "GTg5-2S2kgxIiMLXQbGWkzmxNAGWU-NxA4copGCfB1k",
  },
  category: "technology",
};

// Données structurées (schema.org) : ce que les moteurs ET les IA lisent pour
// comprendre sans ambiguïté ce qu'est Linkup. Pas de note/avis inventés.
const JSON_LD = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: `${SITE_URL}/`,
      name: "Linkup",
      description: LONG_DESCRIPTION,
      inLanguage: "fr-FR",
    },
    {
      "@type": "FAQPage",
      "@id": `${SITE_URL}/#faq`,
      mainEntity: FAQ.map((f) => ({
        "@type": "Question",
        name: f.q,
        acceptedAnswer: { "@type": "Answer", text: f.a },
      })),
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${SITE_URL}/#app`,
      name: "Linkup",
      applicationCategory: "UtilitiesApplication",
      operatingSystem: "Android 8+, Linux",
      url: `${SITE_URL}/`,
      description: LONG_DESCRIPTION,
      inLanguage: "fr-FR",
      isAccessibleForFree: true,
      offers: { "@type": "Offer", price: "0", priceCurrency: "EUR" },
      downloadUrl: [
        "https://linkup.sahelstack.tech/dl/linkup.apk",
        "https://linkup.sahelstack.tech/dl/linkup.AppImage",
        "https://linkup.sahelstack.tech/dl/linkup-pc.deb",
      ],
      featureList: [
        "Transfert de fichiers entre téléphone et PC sur le réseau local",
        "Envoi de photos et vidéos depuis la galerie",
        "Presse-papier partagé téléphone ⇄ PC",
        "Appairage par scan d'un QR code, sans compte",
        "Aucune donnée dans le cloud : tout reste sur le réseau local",
      ],
      screenshot: `${SITE_URL}/og.png`,
      softwareVersion: "0.6",
      author: { "@type": "Person", name: "Mahamane Korobara" },
    },
  ],
};

export default function RootLayout({ children }) {
  return (
    <html lang="fr" className={geist.variable}>
      <body>
        {children}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD) }}
        />
      </body>
    </html>
  );
}
