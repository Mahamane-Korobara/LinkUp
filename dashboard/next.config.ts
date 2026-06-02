import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Sortie autonome (server.js + node_modules minimal) pour le paquet .deb :
  // le service systemd lance `node server.js` sans npm ni build sur la machine.
  output: "standalone",
};

export default nextConfig;
