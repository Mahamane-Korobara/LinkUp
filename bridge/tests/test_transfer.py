"""Tests S4.J1 — transfert de fichiers chunké (service + routes)."""

import hashlib
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.deps import get_transfer_service, require_transfer_auth, transfer_token
from app.routes import transfer as transfer_routes
from app.services import transfer as transfer_module
from app.services.transfer import TransferError, TransferService

DEV_TOKEN = "test-token-pytest-only-do-not-use-in-prod"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@pytest.fixture
def service(tmp_path):
    return TransferService(
        staging_dir=tmp_path / "staging",
        inbox_dir=tmp_path / "inbox",
    )


# ----------------------------------------------------------------- service unit


def test_save_chunk_then_finalize_roundtrip(service):
    chunks = [b"hello ", b"chunked ", b"world!"]
    full = b"".join(chunks)
    for i, c in enumerate(chunks):
        service.save_chunk("tx1", i, c, sha(c))

    assert service.received_chunks("tx1") == [0, 1, 2]

    dest = service.finalize("tx1", "demo.txt", total_chunks=3, sha256_hex=sha(full))

    assert dest.read_bytes() == full
    assert dest.name == "demo.txt"
    # rangé dans le sous-dossier « fichiers » (extension non média)
    assert dest.parent == service._inbox / "fichiers"
    # staging nettoyé après finalize
    assert service.received_chunks("tx1") == []


def test_finalize_classes_media_into_subfolders(service):
    cases = {"photo.jpg": "photos", "clip.MP4": "video", "notes.pdf": "fichiers"}
    for i, (name, sub) in enumerate(cases.items()):
        tx = f"tx-media-{i}"
        service.save_chunk(tx, 0, b"x", sha(b"x"))
        dest = service.finalize(tx, name, total_chunks=1, sha256_hex=sha(b"x"))
        assert dest.parent == service._inbox / sub
        # le finalize re-localise le fichier par son chemin relatif
        assert service.resolve_in_inbox(f"{sub}/{name}") == dest.resolve()


def test_save_chunk_rejects_bad_chunk_checksum(service):
    with pytest.raises(TransferError, match="SHA-256 du chunk"):
        service.save_chunk("tx2", 0, b"data", sha(b"different"))
    # rien n'a été écrit
    assert service.received_chunks("tx2") == []


def test_finalize_rejects_missing_chunk(service):
    service.save_chunk("tx3", 0, b"a", sha(b"a"))
    service.save_chunk("tx3", 2, b"c", sha(b"c"))  # il manque l'index 1
    with pytest.raises(TransferError, match="chunks manquants"):
        service.finalize("tx3", "f.bin", total_chunks=3, sha256_hex=sha(b"ac"))


def test_finalize_rejects_bad_global_checksum(service):
    service.save_chunk("tx4", 0, b"abc", sha(b"abc"))
    with pytest.raises(TransferError, match="SHA-256 global"):
        service.finalize("tx4", "f.bin", total_chunks=1, sha256_hex=sha(b"WRONG"))
    # le .part a été nettoyé, pas de fichier corrompu dans l'inbox
    assert not (service._inbox / "f.bin").exists()


def test_received_chunks_supports_resume(service):
    service.save_chunk("tx5", 0, b"x", sha(b"x"))
    service.save_chunk("tx5", 3, b"y", sha(b"y"))
    assert service.received_chunks("tx5") == [0, 3]


def test_rejects_path_traversal_transfer_id(service):
    with pytest.raises(TransferError, match="transfer_id invalide"):
        service.save_chunk("../evil", 0, b"x", sha(b"x"))


def test_open_in_inbox_opens_existing_file(service, monkeypatch):
    opened = []
    monkeypatch.setattr(transfer_module, "_open_with_os", lambda p: opened.append(p))

    service._inbox.mkdir(parents=True, exist_ok=True)
    (service._inbox / "photo.jpg").write_bytes(b"img")

    result = service.open_in_inbox("photo.jpg")
    assert result.name == "photo.jpg"
    assert opened == [result]


def test_resolve_in_inbox_falls_back_to_legacy_flat_dir(tmp_path, monkeypatch):
    legacy = tmp_path / "Inbox"
    legacy.mkdir(parents=True)
    (legacy / "old.jpg").write_bytes(b"img")
    svc = TransferService(
        staging_dir=tmp_path / "staging",
        inbox_dir=tmp_path / "Transfert",
        legacy_inbox_dirs=(legacy,),
    )
    # stored_name au format relatif « photos/old.jpg » mais fichier réellement
    # dans l'ancien dossier plat → résolu par basename dans la racine legacy.
    assert svc.resolve_in_inbox("photos/old.jpg") == (legacy / "old.jpg").resolve()
    assert svc.resolve_in_inbox("old.jpg") == (legacy / "old.jpg").resolve()


def test_open_in_inbox_rejects_unknown_file(service, monkeypatch):
    monkeypatch.setattr(transfer_module, "_open_with_os", lambda p: None)
    service._inbox.mkdir(parents=True, exist_ok=True)
    with pytest.raises(TransferError, match="introuvable"):
        service.open_in_inbox("nope.txt")


def test_open_in_inbox_neutralizes_traversal(service, monkeypatch):
    # `../../etc/passwd` → basename `passwd` → cherché DANS l'inbox uniquement.
    monkeypatch.setattr(transfer_module, "_open_with_os", lambda p: None)
    service._inbox.mkdir(parents=True, exist_ok=True)
    with pytest.raises(TransferError):
        service.open_in_inbox("../../etc/passwd")


def test_open_with_os_raises_on_launcher_failure(monkeypatch):
    """Régression : `xdg-open`/`open` qui échoue (pas de session graphique,
    aucune appli associée…) doit lever TransferError. Avant, Popen sans check
    rendait la main aussitôt → le endpoint répondait 200 et le tél affichait
    « ouvert » alors que RIEN ne s'ouvrait sur le PC."""

    class _FakeProc:
        returncode = 3

        def communicate(self, timeout=None):
            return (b"", b"cannot open display")

    monkeypatch.setattr(transfer_module.subprocess, "Popen", lambda *a, **k: _FakeProc())
    with pytest.raises(TransferError, match="n'a pas pu ouvrir"):
        transfer_module._open_with_os(Path("/tmp/whatever.jpg"))


def test_open_with_os_succeeds_when_launcher_exits_zero(monkeypatch):
    """Le lanceur fork l'appli et sort en 0 → succès, pas d'exception."""

    class _FakeProc:
        returncode = 0

        def communicate(self, timeout=None):
            return (b"", b"")

    monkeypatch.setattr(transfer_module.subprocess, "Popen", lambda *a, **k: _FakeProc())
    transfer_module._open_with_os(Path("/tmp/whatever.jpg"))  # ne lève pas


def test_open_with_os_treats_long_running_viewer_as_success(monkeypatch):
    """Si le lanceur reste vivant au-delà du délai (il a exec() l'appli en
    place), on considère ça comme un succès plutôt que d'attendre indéfiniment."""

    class _FakeProc:
        returncode = None

        def communicate(self, timeout=None):
            raise transfer_module.subprocess.TimeoutExpired(cmd="xdg-open", timeout=timeout)

    monkeypatch.setattr(transfer_module.subprocess, "Popen", lambda *a, **k: _FakeProc())
    transfer_module._open_with_os(Path("/tmp/whatever.jpg"))  # ne lève pas


def test_desktop_env_strips_snap_polluting_vars(monkeypatch):
    """Variables GTK/GIO pointant vers un snap (ex. terminal VS Code) retirées —
    sinon la visionneuse snap (eog…) plante au lancement (régression dashboard
    « {"ok":true} mais rien ne s'ouvre »)."""
    monkeypatch.setenv("GTK_PATH", "/snap/code/241/usr/lib/x86_64-linux-gnu/gtk-3.0")
    monkeypatch.setenv("GIO_MODULE_DIR", "/home/u/snap/code/common/.cache/gio-modules")
    monkeypatch.setenv("DISPLAY", ":0")  # non-snap → conservée

    env = transfer_module._desktop_env()

    assert "GTK_PATH" not in env
    assert "GIO_MODULE_DIR" not in env
    assert env["DISPLAY"] == ":0"


def test_desktop_env_keeps_non_snap_vars(monkeypatch):
    monkeypatch.setenv("GTK_PATH", "/usr/lib/x86_64-linux-gnu/gtk-3.0")
    assert transfer_module._desktop_env()["GTK_PATH"] == "/usr/lib/x86_64-linux-gnu/gtk-3.0"


def test_finalize_sanitizes_filename_and_avoids_collision(service):
    # nom avec chemin → seul le basename est gardé
    service.save_chunk("a", 0, b"1", sha(b"1"))
    d1 = service.finalize("a", "/etc/passwd", total_chunks=1, sha256_hex=sha(b"1"))
    # passwd n'a pas d'extension média → sous-dossier « fichiers », basename seul
    assert d1.parent == service._inbox / "fichiers"
    assert d1.name == "passwd"

    # même nom → suffixe (1)
    service.save_chunk("b", 0, b"2", sha(b"2"))
    d2 = service.finalize("b", "passwd", total_chunks=1, sha256_hex=sha(b"2"))
    assert d2.name == "passwd (1)"


# --------------------------------------------------------------- routes (HTTP)


def make_client(service: TransferService, *, with_auth_override: bool = True) -> TestClient:
    """Mini-app isolée : inclut juste le router transfert, sans lifespan (donc
    sans démarrer zeroconf)."""
    app = FastAPI()
    app.include_router(transfer_routes.router)
    app.dependency_overrides[get_transfer_service] = lambda: service
    if with_auth_override:
        app.dependency_overrides[require_transfer_auth] = lambda: None
    return TestClient(app)


def test_http_upload_status_finalize_flow(service):
    client = make_client(service)
    chunks = [b"AAA", b"BBB"]
    full = b"".join(chunks)
    for i, c in enumerate(chunks):
        r = client.post(
            "/transfer/upload",
            content=c,
            headers={
                "X-Transfer-Id": "http1",
                "X-Chunk-Index": str(i),
                "X-Chunk-Sha256": sha(c),
            },
        )
        assert r.status_code == 200, r.text

    r = client.get("/transfer/http1/status")
    assert r.json()["received_chunks"] == [0, 1]

    r = client.post(
        "/transfer/http1/finalize",
        headers={
            "X-Transfer-Filename": "up.bin",
            "X-Transfer-Total-Chunks": "2",
            "X-Transfer-Sha256": sha(full),
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["size"] == len(full)
    # .bin → sous-dossier « fichiers » ; le finalize renvoie le chemin relatif
    assert r.json()["filename"] == "fichiers/up.bin"
    assert (service._inbox / "fichiers" / "up.bin").read_bytes() == full


def test_http_upload_bad_checksum_returns_422(service):
    client = make_client(service)
    r = client.post(
        "/transfer/upload",
        content=b"data",
        headers={
            "X-Transfer-Id": "http2",
            "X-Chunk-Index": "0",
            "X-Chunk-Sha256": sha(b"nope"),
        },
    )
    assert r.status_code == 422


def test_http_requires_token(service):
    # Sans override d'auth ET sans header Bearer → 401.
    client = make_client(service, with_auth_override=False)
    r = client.get("/transfer/whatever/status")
    assert r.status_code == 401

    # Avec le token agent complet → 200.
    r = client.get(
        "/transfer/whatever/status",
        headers={"Authorization": f"Bearer {DEV_TOKEN}"},
    )
    assert r.status_code == 200


def test_scoped_transfer_token_only_authorizes_its_own_id(service):
    client = make_client(service, with_auth_override=False)
    tid = "tx-scoped-1"
    scoped = transfer_token(tid)

    # Le token scopé autorise SON transfer_id (via header X-Transfer-Id à l'upload).
    r = client.post(
        "/transfer/upload",
        content=b"Z",
        headers={
            "Authorization": f"Bearer {scoped}",
            "X-Transfer-Id": tid,
            "X-Chunk-Index": "0",
            "X-Chunk-Sha256": sha(b"Z"),
        },
    )
    assert r.status_code == 200, r.text

    # …et son statut (via path param).
    assert client.get(f"/transfer/{tid}/status", headers={"Authorization": f"Bearer {scoped}"}).status_code == 200

    # Mais PAS un autre transfer_id → 401.
    r = client.get(
        "/transfer/another-id/status",
        headers={"Authorization": f"Bearer {scoped}"},
    )
    assert r.status_code == 401


def test_transfer_token_matches_cross_language_vector(monkeypatch):
    """Parité cross-langage avec Laravel TransferTokenSigner::sign() : un même
    (secret, transfer_id) DOIT produire le même token des deux côtés. Cf. le test
    'shared cross-language HMAC vector' côté agent."""
    from app.config import settings

    monkeypatch.setattr(settings, "agent_token", "linkup-shared-secret")
    assert transfer_token("tx-vector-001") == "e63NlNJ4QLrsy7kuevHeTZsG9_ryAd2rya-K8uq0RwA"
