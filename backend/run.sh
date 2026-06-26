#!/usr/bin/env bash
# Launch the Career AI backend.
set -e
cd "$(dirname "$0")"

if [ ! -d venv ]; then
  python3 -m venv venv
  ./venv/bin/pip install --upgrade pip
  ./venv/bin/pip install -r requirements.txt
fi

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8077}"
echo "Career AI backend -> http://$HOST:$PORT  (docs: /docs)"
exec ./venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
