"""Service de transfert de fichiers chunké (S4.J1).

Reçoit un fichier découpé en chunks (par le tél via `dio`, ou par Laravel pour
le sens PC→tél), vérifie le SHA-256 de chaque chunk à la réception, puis
recompose et vérifie le SHA-256 global au finalize. Supporte la reprise : on
peut redemander la liste des chunks déjà reçus et n'envoyer que les manquants.

Layout disque :
    <staging>/<transfer_id>/chunk_000000, chunk_000001, ...   (temporaire)
    <inbox>/<filename>                                        (finalisé)
"""

from __future__ import annotations

import hashlib
import re
import shutil
from pathlib import Path

# transfer_id : on n'accepte qu'un token sûr (UUID/hex/base64url), jamais de
# `..` ou de `/` qui permettraient une évasion hors du dossier de staging.
_SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")

_CHUNK_GLOB = "chunk_*"


class TransferError(Exception):
    """Erreur métier de transfert (checksum, chunk manquant, id invalide)."""


class TransferService:
    def __init__(self, staging_dir: Path, inbox_dir: Path) -> None:
        self._staging = Path(staging_dir)
        self._inbox = Path(inbox_dir)

    # ------------------------------------------------------------------ utils

    def _safe_id(self, transfer_id: str) -> str:
        if not _SAFE_ID.match(transfer_id):
            raise TransferError(f"transfer_id invalide : {transfer_id!r}")
        return transfer_id

    def _chunk_dir(self, transfer_id: str) -> Path:
        return self._staging / self._safe_id(transfer_id)

    @staticmethod
    def _chunk_name(index: int) -> str:
        if index < 0:
            raise TransferError(f"index de chunk négatif : {index}")
        return f"chunk_{index:06d}"

    @staticmethod
    def _sha256(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()

    # ------------------------------------------------------------------ upload

    def save_chunk(self, transfer_id: str, index: int, data: bytes, sha256_hex: str) -> None:
        """Écrit un chunk après avoir vérifié son SHA-256. Idempotent (réécrit)."""
        actual = self._sha256(data)
        if actual.lower() != sha256_hex.strip().lower():
            raise TransferError(
                f"SHA-256 du chunk {index} invalide (attendu {sha256_hex}, reçu {actual})"
            )
        chunk_dir = self._chunk_dir(transfer_id)
        chunk_dir.mkdir(parents=True, exist_ok=True)
        # Écriture atomique : tmp puis rename, pour ne jamais laisser un chunk
        # à moitié écrit si le process meurt en plein milieu.
        tmp = chunk_dir / f".{self._chunk_name(index)}.part"
        tmp.write_bytes(data)
        tmp.replace(chunk_dir / self._chunk_name(index))

    def received_chunks(self, transfer_id: str) -> list[int]:
        """Indices des chunks déjà reçus, triés (pour la reprise)."""
        chunk_dir = self._chunk_dir(transfer_id)
        if not chunk_dir.is_dir():
            return []
        indices: list[int] = []
        for path in chunk_dir.glob(_CHUNK_GLOB):
            try:
                indices.append(int(path.name.removeprefix("chunk_")))
            except ValueError:
                continue
        return sorted(indices)

    # ---------------------------------------------------------------- finalize

    def finalize(
        self, transfer_id: str, filename: str, total_chunks: int, sha256_hex: str
    ) -> Path:
        """Recompose les chunks dans l'ordre, vérifie le SHA-256 global, déplace
        vers l'inbox, puis nettoie le staging. Throws TransferError si un chunk
        manque ou si le checksum global ne correspond pas.
        """
        if total_chunks <= 0:
            raise TransferError("total_chunks doit être > 0")

        chunk_dir = self._chunk_dir(transfer_id)
        received = set(self.received_chunks(transfer_id))
        missing = [i for i in range(total_chunks) if i not in received]
        if missing:
            raise TransferError(f"chunks manquants : {missing[:10]} (… {len(missing)} au total)")

        self._inbox.mkdir(parents=True, exist_ok=True)
        dest = self._unique_destination(filename)

        hasher = hashlib.sha256()
        tmp_out = dest.with_suffix(dest.suffix + ".part")
        with tmp_out.open("wb") as out:
            for index in range(total_chunks):
                data = (chunk_dir / self._chunk_name(index)).read_bytes()
                hasher.update(data)
                out.write(data)

        actual = hasher.hexdigest()
        if actual.lower() != sha256_hex.strip().lower():
            tmp_out.unlink(missing_ok=True)
            raise TransferError(
                f"SHA-256 global invalide (attendu {sha256_hex}, reçu {actual})"
            )

        tmp_out.replace(dest)
        self.cleanup(transfer_id)
        return dest

    def cleanup(self, transfer_id: str) -> None:
        """Supprime le dossier de staging du transfert. Idempotent."""
        shutil.rmtree(self._chunk_dir(transfer_id), ignore_errors=True)

    # ------------------------------------------------------------------ helpers

    def _unique_destination(self, filename: str) -> Path:
        """Nom de fichier sûr (basename only) et non-collision dans l'inbox.

        `Path(filename).name` neutralise tout `../` ou chemin absolu. Si le nom
        existe déjà, on suffixe ` (1)`, ` (2)`, … pour ne pas écraser.
        """
        safe = Path(filename).name.strip() or "fichier"
        candidate = self._inbox / safe
        if not candidate.exists():
            return candidate

        stem = Path(safe).stem
        suffix = Path(safe).suffix
        counter = 1
        while True:
            candidate = self._inbox / f"{stem} ({counter}){suffix}"
            if not candidate.exists():
                return candidate
            counter += 1
