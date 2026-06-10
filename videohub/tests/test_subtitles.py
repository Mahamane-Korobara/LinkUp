from app.services.subtitles import clean_vtt

# Auto-captions YouTube : « rolling window » — chaque cue répète la fin du
# précédent. Le nettoyage doit dédupliquer au niveau des mots.
ROLLING_VTT = """WEBVTT

00:00:00.000 --> 00:00:02.000
bonjour à tous

00:00:02.000 --> 00:00:04.000
bonjour à tous et bienvenue

00:00:04.000 --> 00:00:06.000
et bienvenue sur la chaîne
"""

# Sous-titres manuels (déjà ponctués) avec une grande pause → 2 paragraphes.
MANUAL_VTT = """WEBVTT

00:00:00.000 --> 00:00:02.000
Bonjour, ceci est la première partie.

00:00:10.000 --> 00:00:12.000
Et voici la seconde partie, après une pause.
"""

TAGGED_VTT = """WEBVTT

00:00:00.000 --> 00:00:02.000
<00:00:00.500><c>bonjour</c> le monde
"""


def test_rolling_dedup_collapses_repeats():
    paras = clean_vtt(ROLLING_VTT)
    text = " ".join(paras).lower()
    # « bonjour à tous » ne doit apparaître qu'une fois malgré la répétition.
    assert text.count("bonjour à tous") == 1
    assert "bienvenue sur la chaîne" in text


def test_manual_gap_splits_paragraphs():
    paras = clean_vtt(MANUAL_VTT, gap_seconds=2.0)
    assert len(paras) == 2
    assert paras[0].startswith("Bonjour")
    assert paras[1].startswith("Et voici")


def test_inline_tags_stripped():
    paras = clean_vtt(TAGGED_VTT)
    assert paras == ["bonjour le monde"]


def test_empty_input():
    assert clean_vtt("") == []
    assert clean_vtt("WEBVTT\n") == []
