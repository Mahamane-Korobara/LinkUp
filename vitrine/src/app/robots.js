const SITE_URL = "https://linkup-landing.sahelstack.tech";

// On AUTORISE explicitement les robots IA (c'est ce qui compte réellement pour
// le GEO : leur permettre de lire le site, contrairement à llms.txt qu'ils
// n'utilisent pas). Liste des user-agents IA connus (juin 2026).
const AI_BOTS = [
  "GPTBot",
  "ChatGPT-User",
  "OAI-SearchBot",
  "ClaudeBot",
  "Claude-Web",
  "anthropic-ai",
  "PerplexityBot",
  "Perplexity-User",
  "Google-Extended",
  "Applebot-Extended",
  "Bytespider",
  "CCBot",
  "Amazonbot",
  "Meta-ExternalAgent",
];

export default function robots() {
  return {
    rules: [
      { userAgent: "*", allow: "/" },
      { userAgent: AI_BOTS, allow: "/" },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
