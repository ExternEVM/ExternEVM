#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CONTRACTS_DIR="$ROOT/contracts"
RPC="http://127.0.0.1:8545"
PRIVKEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
CONTRACT_FILE="$ROOT/.contract_address"

echo "==> Building contracts..."
cd "$CONTRACTS_DIR"
forge build --silent

echo "==> Deploying ExternApiDemo to ExternEVM (chain 22042004)..."
DEPLOY_OUTPUT=$(forge create src/ExternApiDemo.sol:ExternApiDemo \
  --rpc-url "$RPC" \
  --private-key "$PRIVKEY" \
  --broadcast 2>&1)

CONTRACT_ADDR=$(echo "$DEPLOY_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [[ -z "$CONTRACT_ADDR" ]]; then
  echo "ERROR: Could not parse contract address from forge output:"
  echo "$DEPLOY_OUTPUT"
  exit 1
fi

echo "$CONTRACT_ADDR" > "$CONTRACT_FILE"
echo ""
echo "==> ExternApiDemo deployed."
echo "    Address: $CONTRACT_ADDR"
echo "    Saved to: $CONTRACT_FILE"
echo ""
echo "    Test with:"
echo "      cast call $CONTRACT_ADDR 'getBitcoinPrice()(uint256)' --rpc-url $RPC"