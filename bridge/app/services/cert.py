"""CA Linkup + certificat serveur pour le HTTPS du Dev Preview.

Pourquoi une CA maison : on sert les projets sur `https://<ip-LAN>:port`, une IP
privée pour laquelle aucune CA publique ne signera de certificat. On crée donc
une **CA Linkup** (racine auto-signée, générée une fois), on fabrique des
certificats serveur signés par elle, et le tél **approuve la CA une seule fois**
→ tous les projets Linkup deviennent « contexte sécurisé » (caméra/PWA/géoloc).

Tout est en `cryptography` (Python pur, bundlable PyInstaller, zéro droit admin).
La **clé de la CA reste sur le PC** et n'est jamais exposée ; seul le certificat
public (`linkup-ca.crt`) est téléchargé par le tél.
"""

import datetime
import ipaddress
import socket
import ssl
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

_CA_VALIDITY_DAYS = 3650  # 10 ans : la confiance posée sur le tél doit durer
_SERVER_VALIDITY_DAYS = 820  # < 825 j (limites navigateurs), régénéré au démarrage
_KEY_SIZE = 2048


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.UTC)


def local_ips() -> set[str]:
    """IPv4 locales à mettre dans le SAN du certificat (sinon mismatch d'hôte).

    127.0.0.1 + l'IP LAN principale (route sortante) + celles liées au hostname.
    """
    ips = {"127.0.0.1"}
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))  # pas de trafic réel : juste choisir l'IF sortante
        ips.add(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, family=socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return ips


class CertManager:
    """Possède la CA Linkup et le certificat serveur, persistés sous ``ca_dir``."""

    def __init__(self, ca_dir: Path) -> None:
        self.ca_dir = ca_dir
        self.ca_cert_path = ca_dir / "linkup-ca.crt"
        self.ca_key_path = ca_dir / "linkup-ca.key"
        self.server_cert_path = ca_dir / "server.crt"
        self.server_key_path = ca_dir / "server.key"

    def ensure(self) -> None:
        """Garantit CA + certificat serveur sur disque. Idempotent pour la CA."""
        self.ca_dir.mkdir(parents=True, exist_ok=True)
        ca_cert, ca_key = self._ensure_ca()
        self._issue_server_cert(ca_cert, ca_key)

    def ca_pem(self) -> bytes:
        """Certificat public de la CA (téléchargé par le tél pour l'approuver)."""
        return self.ca_cert_path.read_bytes()

    def ssl_context(self) -> ssl.SSLContext:
        """Contexte TLS serveur prêt pour ``asyncio.start_server(ssl=...)``."""
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(self.server_cert_path, self.server_key_path)
        return ctx

    # ------------------------------------------------------------------ interne

    def _ensure_ca(self) -> tuple[x509.Certificate, rsa.RSAPrivateKey]:
        if self.ca_cert_path.exists() and self.ca_key_path.exists():
            cert = x509.load_pem_x509_certificate(self.ca_cert_path.read_bytes())
            key = serialization.load_pem_private_key(self.ca_key_path.read_bytes(), password=None)
            return cert, key  # type: ignore[return-value]

        key = rsa.generate_private_key(public_exponent=65537, key_size=_KEY_SIZE)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Linkup Local CA")])
        cert = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(_now() - datetime.timedelta(days=1))
            .not_valid_after(_now() + datetime.timedelta(days=_CA_VALIDITY_DAYS))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_cert_sign=True,
                    crl_sign=True,
                    key_encipherment=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .sign(key, hashes.SHA256())
        )
        self._write(self.ca_cert_path, cert.public_bytes(serialization.Encoding.PEM))
        self._write_key(self.ca_key_path, key)
        return cert, key

    def _issue_server_cert(
        self, ca_cert: x509.Certificate, ca_key: rsa.RSAPrivateKey
    ) -> None:
        # Régénéré à chaque ``ensure`` pour suivre l'IP LAN courante (cheap).
        key = rsa.generate_private_key(public_exponent=65537, key_size=_KEY_SIZE)
        san: list[x509.GeneralName] = [x509.DNSName("localhost")]
        for ip in sorted(local_ips()):
            try:
                san.append(x509.IPAddress(ipaddress.ip_address(ip)))
            except ValueError:
                continue
        cert = (
            x509.CertificateBuilder()
            .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Linkup Bridge")]))
            .issuer_name(ca_cert.subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(_now() - datetime.timedelta(days=1))
            .not_valid_after(_now() + datetime.timedelta(days=_SERVER_VALIDITY_DAYS))
            .add_extension(x509.SubjectAlternativeName(san), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(
                x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
            )
            .sign(ca_key, hashes.SHA256())
        )
        self._write(self.server_cert_path, cert.public_bytes(serialization.Encoding.PEM))
        self._write_key(self.server_key_path, key)

    @staticmethod
    def _write(path: Path, data: bytes) -> None:
        path.write_bytes(data)

    @staticmethod
    def _write_key(path: Path, key: rsa.RSAPrivateKey) -> None:
        path.write_bytes(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
        # Clé privée : lecture/écriture propriétaire uniquement.
        try:
            path.chmod(0o600)
        except OSError:
            pass
