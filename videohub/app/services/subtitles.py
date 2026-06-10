"""Nettoyage HEURISTIQUE des sous-titres VTT → texte lisible.

Deux pièges des sous-titres :
- **Auto-captions YouTube** : « rolling window » — chaque cue répète la fin du
  cue précédent plus un mot. Concaténer brutalement triple le texte.
- **Balises inline** : `<00:00:01.234>`, `<c>...</c>` au milieu des mots.

On résout par un **dédup au niveau des mots** (on n'ajoute que la partie qui
chevauche pas la fin du flux déjà accumulé), puis on **coupe en paragraphes** sur
les pauses temporelles. Pour des sous-titres MANUELS (déjà ponctués, sans
chevauchement), le dédup ne fait rien et seul le découpage en paragraphes opère —
ce qui donne déjà un vrai document propre.
"""

import io
import re

import webvtt

_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"\s+")
# Combien de mots de recouvrement on cherche au max entre deux cues consécutifs.
_MAX_OVERLAP = 14


def _clean(text: str) -> str:
    """Retire les balises et normalise les espaces d'une ligne de cue."""
    return _WS.sub(" ", _TAG.sub("", text.replace("\n", " "))).strip()


def _parse_cues(vtt_text: str) -> list[tuple[float, float, str]]:
    """Renvoie [(start_s, end_s, texte_propre)] ; [] si le VTT est illisible."""
    try:
        cues = []
        for c in webvtt.from_buffer(io.StringIO(vtt_text)):
            txt = _clean(c.text)
            if txt:
                cues.append((c.start_in_seconds, c.end_in_seconds, txt))
        return cues
    except Exception:
        # VTT malformé : repli grossier — on retire timestamps/balises ligne à ligne.
        lines = []
        for raw in vtt_text.splitlines():
            line = raw.strip()
            if not line or line == "WEBVTT" or "-->" in line or line.isdigit():
                continue
            cleaned = _clean(line)
            if cleaned:
                lines.append(cleaned)
        return [(0.0, 0.0, line) for line in lines]


def clean_vtt(vtt_text: str, gap_seconds: float = 2.2) -> list[str]:
    """VTT brut → liste de paragraphes propres (sans doublons de défilement)."""
    cues = _parse_cues(vtt_text)
    if not cues:
        return []

    stream: list[str] = []  # flux de mots dédupliqué
    breaks: set[int] = set()  # indices (dans `stream`) où démarre un nouveau paragraphe
    last_end: float | None = None

    for start, end, txt in cues:
        words = txt.split()
        if not words:
            continue

        # Recouvrement entre la FIN du flux et le DÉBUT du cue courant.
        overlap = 0
        for k in range(min(_MAX_OVERLAP, len(words), len(stream)), 0, -1):
            if [w.lower() for w in stream[-k:]] == [w.lower() for w in words[:k]]:
                overlap = k
                break
        new_words = words[overlap:]
        if not new_words:
            last_end = end or last_end
            continue

        # Coupure de paragraphe AVANT d'ajouter, si la pause est assez longue.
        if last_end is not None and start - last_end > gap_seconds and stream:
            breaks.add(len(stream))
        stream.extend(new_words)
        last_end = end or last_end

    if not stream:
        return []

    # Reconstruit les paragraphes à partir des points de coupure.
    paragraphs: list[str] = []
    cursor = 0
    for idx in sorted(breaks):
        if idx > cursor:
            paragraphs.append(" ".join(stream[cursor:idx]))
            cursor = idx
    paragraphs.append(" ".join(stream[cursor:]))
    return [p.strip() for p in paragraphs if p.strip()]
