import { redirect } from "next/navigation";

/**
 * Racine du dashboard : pas de page d'accueil dédiée pour l'instant, on
 * redirige vers la liste des téléphones (le point d'entrée utile).
 */
export default function Home() {
  redirect("/devices");
}
