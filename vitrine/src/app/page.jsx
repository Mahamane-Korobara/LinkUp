import ScrollProgress from "@/components/landing/ScrollProgress";
import Navbar from "@/components/landing/Navbar";
import HeroSection from "@/components/landing/hero";
import Problem from "@/components/landing/sections/Problem";
import HowItWorks from "@/components/landing/sections/HowItWorks";
import Features from "@/components/landing/sections/Features";
import Privacy from "@/components/landing/sections/Privacy";
import Comparison from "@/components/landing/sections/Comparison";
import DownloadSection from "@/components/landing/sections/Download";
import Footer from "@/components/landing/sections/Footer";

export default function Home() {
  return (
    <main className="min-h-screen bg-[color:var(--background)]">
      <ScrollProgress />
      <Navbar />
      <HeroSection />
      <Problem />
      <HowItWorks />
      <Features />
      <Privacy />
      <Comparison />
      <DownloadSection />
      <Footer />
    </main>
  );
}
