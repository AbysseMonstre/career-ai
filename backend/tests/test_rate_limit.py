"""Rate limiting must bucket per real visitor, not per hosting proxy.

Behind Render every request shares one socket peer, so without X-Forwarded-For
the whole internet competes for a single quota (and one user locks everyone
out, while an attacker is barely slowed).
"""
import os

os.environ.setdefault("CAREER_AI_SECRET", "rate-limit-test-secret")

from fastapi.testclient import TestClient  # noqa: E402

from app import security  # noqa: E402
from app.main import app  # noqa: E402

client = TestClient(app)


def _register(ip, n):
    """Attempt n registrations from one apparent client; return status codes."""
    out = []
    for i in range(n):
        r = client.post(
            "/auth/register",
            headers={"X-Forwarded-For": f"10.0.0.1, {ip}"},
            json={"email": f"rl{ip.replace('.', '')}{i}@example.com", "name": "RL",
                  "password": "Test12345!", "role": "seeker", "consent": True},
        )
        out.append(r.status_code)
    return out


def setup_function():
    security._hits.clear()


def test_one_visitor_is_capped():
    codes = _register("203.0.113.7", 7)
    assert 429 in codes, f"jamais limité: {codes}"
    assert codes.count(200) <= 5, f"plus de 5 inscriptions passées: {codes}"


def test_visitors_do_not_share_a_quota():
    """The bug this guards: one busy user must not lock out everybody else."""
    _register("203.0.113.8", 6)          # exhausts their own bucket
    codes = _register("203.0.113.9", 1)  # a different visitor
    assert codes == [200], f"un autre visiteur a été bloqué: {codes}"


def test_spoofed_leading_hops_are_ignored():
    """Only the hop the proxy appends counts, so forging the header is futile."""
    for i in range(6):
        client.post(
            "/auth/register",
            headers={"X-Forwarded-For": f"1.2.3.{i}, 203.0.113.10"},
            json={"email": f"spoof{i}@example.com", "name": "S",
                  "password": "Test12345!", "role": "seeker", "consent": True},
        )
    r = client.post(
        "/auth/register",
        headers={"X-Forwarded-For": "9.9.9.9, 203.0.113.10"},
        json={"email": "spoof-last@example.com", "name": "S",
              "password": "Test12345!", "role": "seeker", "consent": True},
    )
    assert r.status_code == 429, "le bucket a été contourné en changeant le premier hop"
