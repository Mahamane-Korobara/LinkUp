"""Tests de validation Settings (config.py).

Garantit que le bridge refuse de démarrer si le token placeholder est gardé,
et accepte les valeurs valides (cf. ADR-002).
"""

import os

import pytest
from pydantic import ValidationError

from app.config import PLACEHOLDER_TOKEN, Settings


def _settings_from_env(env: dict[str, str]) -> Settings:
    """Construit Settings à partir d'un dict d'env vars, en isolant les LINKUP_*."""
    backup = {k: os.environ.pop(k) for k in list(os.environ) if k.startswith("LINKUP_BRIDGE_")}
    try:
        for k, v in env.items():
            os.environ[k] = v
        return Settings(_env_file=None)  # type: ignore[arg-type]
    finally:
        for k in list(os.environ):
            if k.startswith("LINKUP_BRIDGE_"):
                del os.environ[k]
        os.environ.update(backup)


def test_settings_refuse_placeholder_token():
    with pytest.raises(ValidationError) as exc:
        _settings_from_env({"LINKUP_BRIDGE_AGENT_TOKEN": PLACEHOLDER_TOKEN})
    assert "placeholder" in str(exc.value).lower()


def test_settings_refuse_low_entropy_token():
    # 16 caractères mais 1 seul caractère distinct
    with pytest.raises(ValidationError) as exc:
        _settings_from_env({"LINKUP_BRIDGE_AGENT_TOKEN": "a" * 16})
    assert "entropie" in str(exc.value).lower()


def test_settings_refuse_missing_token():
    with pytest.raises(ValidationError):
        _settings_from_env({})


def test_settings_refuse_too_short_token():
    with pytest.raises(ValidationError):
        _settings_from_env({"LINKUP_BRIDGE_AGENT_TOKEN": "tooshort"})


def test_settings_refuse_invalid_port():
    with pytest.raises(ValidationError):
        _settings_from_env(
            {
                "LINKUP_BRIDGE_AGENT_TOKEN": "valid-token-pytest-only-do-not-use",
                "LINKUP_BRIDGE_PORT": "99999",
            }
        )


def test_settings_accept_valid_config():
    settings = _settings_from_env(
        {"LINKUP_BRIDGE_AGENT_TOKEN": "valid-token-pytest-only-do-not-use"}
    )
    assert settings.agent_token == "valid-token-pytest-only-do-not-use"
    assert settings.port == 8765
