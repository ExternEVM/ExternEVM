#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/../.devnet.pids"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No devnet PID file found at $PID_FILE — nothing to stop."
  exit 0
fi

echo "==> Stopping ExternEVM devnet..."
while IFS= read -r pid; do
  if kill -0 "$pid" 2>/dev/null; then
    echo "   Killing PID $pid"
    kill "$pid" 2>/dev/null || true
  fi
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "==> Devnet stopped."