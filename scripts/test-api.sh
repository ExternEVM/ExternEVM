#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CONTRACT_FILE="$ROOT/.contract_address"

if [[ ! -f "$CONTRACT_FILE" ]]; then
  echo "ERROR: No contract address found. Run scripts/deploy-contract.sh first."
  exit 1
fi

CONTRACT=$(cat "$CONTRACT_FILE")
NODES=("http://127.0.0.1:8545" "http://127.0.0.1:8546" "http://127.0.0.1:8547")
NODE_NAMES=("Node1" "Node2" "Node3")

PASS=0
FAIL=0

check() {
  local label="$1"
  local rpc="$2"
  local sig="$3"
  local min="$4"

  result=$(cast call "$CONTRACT" "$sig" --rpc-url "$rpc" 2>&1)
  # strip quotes for string types
  result_clean=$(echo "$result" | tr -d '"')

  if [[ "$result_clean" =~ ^[0-9]+$ ]] && (( result_clean > min )); then
    echo "   [PASS] $label @ $rpc => $result_clean"
    (( PASS++ )) || true
  elif [[ ! "$result_clean" =~ ^[0-9]+$ ]] && [[ -n "$result_clean" ]]; then
    # string return — just check non-empty
    echo "   [PASS] $label @ $rpc => $result_clean"
    (( PASS++ )) || true
  else
    echo "   [FAIL] $label @ $rpc => $result (expected > $min)"
    (( FAIL++ )) || true
  fi
}

echo "==> ExternEVM API precompile integration test"
echo "    Contract: $CONTRACT"
echo ""

echo "--- getBitcoinPrice() ---"
for i in 0 1 2; do
  check "getBitcoinPrice ${NODE_NAMES[$i]}" "${NODES[$i]}" "getBitcoinPrice()(uint256)" 1000
done

echo ""
echo "--- getPeopleInSpace() ---"
for i in 0 1 2; do
  check "getPeopleInSpace ${NODE_NAMES[$i]}" "${NODES[$i]}" "getPeopleInSpace()(uint256)" 0
done

echo ""
echo "--- getISSPosition() ---"
for i in 0 1 2; do
  result=$(cast call "$CONTRACT" "getISSPosition()(string)" --rpc-url "${NODES[$i]}" 2>&1 | tr -d '"')
  if [[ -n "$result" ]]; then
    echo "   [PASS] getISSPosition ${NODE_NAMES[$i]} => $result"
    (( PASS++ )) || true
  else
    echo "   [FAIL] getISSPosition ${NODE_NAMES[$i]} => empty"
    (( FAIL++ )) || true
  fi
done

echo ""
echo "--- getTemperature() ---"
for i in 0 1 2; do
  check "getTemperature ${NODE_NAMES[$i]}" "${NODES[$i]}" "getTemperature()(uint256)" 0
done

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"

if (( FAIL > 0 )); then
  exit 1
fi