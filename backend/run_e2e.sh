#!/usr/bin/env bash
# E2E-Lauf: FastAPI-Backend starten → Godot-E2E-Test → Backend stoppen.
# Backend-Logs und Exit-Codes landen in backend/e2e.log.
set -u
cd "$(dirname "$0")"
LOG="e2e.log"
: > "$LOG"

./.venv/bin/uvicorn main:app --port 8000 > "$LOG" 2>&1 &
BACKEND_PID=$!
echo "Backend gestartet (PID $BACKEND_PID), Log: backend/$LOG"

# Auf den Server warten (max. 30 s)
for _ in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8000/v1/pet/chat > /dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

cd ..
./.tools/Godot_v4.3-stable_linux.x86_64 --headless --path . -s res://tests/check_e2e_backend.gd 2>&1 | grep -iv fontconfig
GODOT_EXIT=${PIPESTATUS[0]}

# Backend EXAKT an seiner PID beenden (kein Namensmuster!)
kill "$BACKEND_PID" 2>/dev/null
wait "$BACKEND_PID" 2>/dev/null

echo "GODOT_E2E_EXIT=$GODOT_EXIT"
exit "$GODOT_EXIT"
