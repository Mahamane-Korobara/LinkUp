"""Tests Dev Preview Lot B — CA Linkup + certificat serveur + relais HTTPS."""

import asyncio
import ssl

import pytest
from cryptography import x509

from app.services.cert import CertManager, local_ips
from app.services.preview import ProxyManager


def test_ensure_creates_ca_and_server(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()
    assert cm.ca_cert_path.exists() and cm.ca_key_path.exists()
    assert cm.server_cert_path.exists() and cm.server_key_path.exists()
    assert cm.ca_pem().startswith(b"-----BEGIN CERTIFICATE-----")


def test_ca_is_a_certificate_authority(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()
    ca = x509.load_pem_x509_certificate(cm.ca_pem())
    constraints = ca.extensions.get_extension_for_class(x509.BasicConstraints).value
    assert constraints.ca is True


def test_server_cert_signed_by_ca_and_covers_loopback(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()
    ca = x509.load_pem_x509_certificate(cm.ca_pem())
    server = x509.load_pem_x509_certificate(cm.server_cert_path.read_bytes())
    assert server.issuer == ca.subject  # signé par la CA
    san = server.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    ips = {str(ip) for ip in san.get_values_for_type(x509.IPAddress)}
    assert "127.0.0.1" in ips


def test_ca_is_stable_across_ensure(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()
    first = x509.load_pem_x509_certificate(cm.ca_pem()).serial_number
    cm.ensure()  # ré-appel : la CA ne doit pas changer (sinon le tél perd la confiance)
    second = x509.load_pem_x509_certificate(cm.ca_pem()).serial_number
    assert first == second


def test_local_ips_includes_loopback():
    assert "127.0.0.1" in local_ips()


async def test_https_relay_trusts_the_ca(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()

    async def backend(reader, writer):
        data = await reader.read(100)
        writer.write(b"echo:" + data)
        await writer.drain()
        writer.close()

    server = await asyncio.start_server(backend, "127.0.0.1", 0)
    target = server.sockets[0].getsockname()[1]
    manager = ProxyManager(host="127.0.0.1", ssl_context=cm.ssl_context())
    assert manager.scheme == "https"
    try:
        info = await manager.expose(target)

        # Client qui fait confiance à la CA Linkup → handshake OK.
        client_ctx = ssl.create_default_context(cafile=str(cm.ca_cert_path))
        client_ctx.check_hostname = False  # on valide la chaîne, pas le nom ici
        reader, writer = await asyncio.open_connection(
            "127.0.0.1", info.listen_port, ssl=client_ctx
        )
        writer.write(b"ping")
        await writer.drain()
        out = await reader.read(100)
        assert out == b"echo:ping"
        writer.close()
    finally:
        await manager.shutdown()
        server.close()
        await server.wait_closed()


async def test_https_rejects_untrusted_client(tmp_path):
    cm = CertManager(ca_dir=tmp_path)
    cm.ensure()
    server = await asyncio.start_server(lambda r, w: w.close(), "127.0.0.1", 0)
    target = server.sockets[0].getsockname()[1]
    manager = ProxyManager(host="127.0.0.1", ssl_context=cm.ssl_context())
    try:
        info = await manager.expose(target)
        # Contexte par défaut (CA système) : ne connaît pas la CA Linkup → refus.
        with pytest.raises(ssl.SSLError):
            await asyncio.open_connection(
                "127.0.0.1", info.listen_port, ssl=ssl.create_default_context()
            )
    finally:
        await manager.shutdown()
        server.close()
        await server.wait_closed()
