#!/usr/bin/env bash
set -uo pipefail

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

check_uint() {
  local label="$1"
  local rpc="$2"
  local sig="$3"
  local min="$4"

  sleep 2
  result=$(cast call --rpc-timeout 30 "$CONTRACT" "$sig" --rpc-url "$rpc" 2>&1)
  result_clean=$(echo "$result" | sed 's/ \[.*\]//' | tr -d '"')

  if [[ "$result_clean" =~ ^[0-9]+$ ]] && [[ "$result_clean" -gt "$min" ]]; then
    echo "   [PASS] $label @ $rpc => $result_clean"
    PASS=$((PASS + 1))
  else
    echo "   [FAIL] $label @ $rpc => $result_clean (expected uint > $min)"
    FAIL=$((FAIL + 1))
  fi
}

check_string() {
  local label="$1"
  local rpc="$2"
  local sig="$3"

  sleep 2
  result=$(cast call --rpc-timeout 30 "$CONTRACT" "$sig" --rpc-url "$rpc" 2>&1 | tr -d '"')

  if [[ -n "$result" ]] && [[ "$result" != "Error"* ]]; then
    echo "   [PASS] $label @ $rpc => $result"
    PASS=$((PASS + 1))
  else
    echo "   [FAIL] $label @ $rpc => empty or error"
    FAIL=$((FAIL + 1))
  fi
}

echo "==> ExternEVM API precompile integration test"
echo "    Contract: $CONTRACT"
echo ""

echo "--- getBitcoinPrice() ---"
for i in 0 1 2; do
  check_uint "getBitcoinPrice ${NODE_NAMES[$i]}" "${NODES[$i]}" "getBitcoinPrice()(uint256)" 1000
done

echo ""
echo "--- getPeopleInSpace() ---"
for i in 0 1 2; do
  check_uint "getPeopleInSpace ${NODE_NAMES[$i]}" "${NODES[$i]}" "getPeopleInSpace()(uint256)" 0
done

echo ""
echo "--- getISSPosition() ---"
for i in 0 1 2; do
  check_string "getISSPosition ${NODE_NAMES[$i]}" "${NODES[$i]}" "getISSPosition()(string)"
done

echo ""
echo "--- getTemperature() ---"
for i in 0 1 2; do
  check_uint "getTemperature ${NODE_NAMES[$i]}" "${NODES[$i]}" "getTemperature()(uint256)" 0
done

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
