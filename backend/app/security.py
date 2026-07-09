"""Auth helpers using only the stdlib (pbkdf2 + hmac-signed tokens).

Avoids native deps (bcrypt/jose) so the backend installs cleanly everywhere.
For production, swap to bcrypt + a real JWT lib and load SECRET from env.
"""
import hashlib
import hmac
import os
import json
import base64
import time
import threading
from collections import defaultdict, deque

from . import config

SECRET = config.SECRET.encode()
TOKEN_TTL = 60 * 60 * 24 * 7  # 7 days
PBKDF2_ROUNDS = 240_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ROUNDS)
    return f"{PBKDF2_ROUNDS}${salt.hex()}${dk.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        rounds_s, salt_hex, dk_hex = stored.split("$")
        rounds = int(rounds_s)
    except ValueError:
        # legacy format: salt$hash with default rounds
        try:
            salt_hex, dk_hex = stored.split("$")
            rounds = 100_000
        except ValueError:
            return False
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), rounds)
    return hmac.compare_digest(dk.hex(), dk_hex)


# --- simple in-memory sliding-window rate limiter ---
_hits = defaultdict(deque)
_lock = threading.Lock()


def rate_limited(key: str, limit: int, window_sec: int) -> bool:
    """Return True if `key` has exceeded `limit` calls within `window_sec`."""
    now = time.time()
    with _lock:
        q = _hits[key]
        while q and q[0] < now - window_sec:
            q.popleft()
        if len(q) >= limit:
            return True
        q.append(now)
        return False


def admin_token_ok(token: str) -> bool:
    return bool(config.ADMIN_TOKEN) and hmac.compare_digest(token or "", config.ADMIN_TOKEN)


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def create_token(user_id: int, role: str) -> str:
    payload = {"uid": user_id, "role": role, "exp": int(time.time()) + TOKEN_TTL}
    body = _b64(json.dumps(payload).encode())
    sig = _b64(hmac.new(SECRET, body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def decode_token(token: str):
    try:
        body, sig = token.split(".")
    except ValueError:
        return None
    expected = _b64(hmac.new(SECRET, body.encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(sig, expected):
        return None
    payload = json.loads(_unb64(body))
    if payload.get("exp", 0) < time.time():
        return None
    return payload


# --- password-reset tokens (short-lived, single purpose) ---
RESET_TTL = 3600  # 1 hour


def create_reset_token(user_id: int) -> str:
    payload = {"uid": user_id, "typ": "reset", "exp": int(time.time()) + RESET_TTL}
    body = _b64(json.dumps(payload).encode())
    sig = _b64(hmac.new(SECRET, body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_reset_token(token: str):
    """Return the user id for a valid reset token, else None."""
    p = decode_token(token)
    if not p or p.get("typ") != "reset":
        return None
    return p.get("uid")
