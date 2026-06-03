import ScrollProgress from "@/components/landing/ScrollProgress";
import Navbar from "@/components/landing/Navbar";
import HeroSection from "@/components/landing/hero";
import Problem from "@/components/landing/sections/Problem";
import HowItWorks from "@/components/landing/sections/HowItWorks";
import Features from "@/components/landing/sections/Features";
import Privacy from "@/components/landing/sections/Privacy";
import Comparison from "@/components/landing/sections/Comparison";
import Faq from "@/components/landing/sections/Faq";
import DownloadSection from "@/components/landing/sections/Download";
import Footer from "@/components/landing/sections/Footer";

export default function Home() {
  return (
    <>
      {/* Lien d'évitement (accessibilité clavier) */}
      <a
        href="#contenu"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[200] focus:rounded-lg focus:bg-zinc-900 focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-white"
      >
        Aller au contenu
      </a>

      <ScrollProgress />
      <Navbar />

      <main id="contenu" className="min-h-screen bg-[color:var(--background)]">
        <HeroSection />
        <Problem />
        <HowItWorks />
        <Features />
        <Privacy />
        <Comparison />
        <Faq />
        <DownloadSection />
      </main>

      <Footer />
    </>
  );
}
