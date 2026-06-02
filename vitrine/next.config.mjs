/** @type {import('next').NextConfig} */
const nextConfig = {
  // Vitrine publique déployée sur Vercel (runtime Node dispo) — pas d'export
  // statique nécessaire. Images distantes (avatars Dicebear) autorisées.
  images: {
    remotePatterns: [{ protocol: "https", hostname: "api.dicebear.com" }],
  },
};

export default nextConfig;
