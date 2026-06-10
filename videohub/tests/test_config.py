import pytest
from pydantic import ValidationError

from app.config import PLACEHOLDER_TOKEN, Settings


def test_placeholder_token_refused():
    with pytest.raises(ValidationError):
        Settings(service_token=PLACEHOLDER_TOKEN)


def test_low_entropy_token_refused():
    with pytest.raises(ValidationError):
        Settings(service_token="aaaaaaaaaaaaaaaa")


def test_valid_token_accepted():
    s = Settings(service_token="A-real-enough-token-9f3b2c8e")
    assert s.port == 8780
    assert s.host == "127.0.0.1"
