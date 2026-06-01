#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
  echo ""
  echo "==> Cleaning up..."
  "$SCRIPT_DIR/stop-devnet.sh" || true
}
trap cleanup EXIT

echo "======================================"
echo "  ExternEVM Integration Test"
echo "======================================"

echo ""
echo "==> Step 1: Build EL binary..."
cd "$SCRIPT_DIR/../reth"
cargo build --release -p reth --bin reth 2>&1 | tail -5

echo ""
echo "==> Step 2: Build CL binary..."
cd "$SCRIPT_DIR/../consensus"
cargo build --release 2>&1 | tail -5

echo ""
echo "==> Step 3: Start devnet..."
"$SCRIPT_DIR/start-devnet.sh"

echo ""
echo "==> Step 4: Waiting 10s for chain to produce initial blocks..."
sleep 10

echo ""
echo "==> Step 5: Deploy ExternApiDemo..."
"$SCRIPT_DIR/deploy-contract.sh"

echo ""
echo "==> Step 6: Waiting 5s for deployment to propagate..."
sleep 5

echo ""
echo "==> Step 7: Run API tests..."
"$SCRIPT_DIR/test-api.sh"

echo ""
echo "==> All tests passed."