#!/bin/bash
# ============================================================
# ExternEVM Health Check
# Verifies the node is running and responsive
# Usage: ./health-check.sh [RPC_URL]
# ============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

RPC_URL="${1:-http://127.0.0.1:8545}"

PASS=0
FAIL=0

check() {
    local name="$1"
    local method="$2"
    local params="$3"
    local expect="$4"

    RESPONSE=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[$params],\"id\":1}" 2>/dev/null || echo "CURL_FAILED")

    if [ "$RESPONSE" = "CURL_FAILED" ]; then
        echo -e "  ${RED}✗ $name — connection failed${NC}"
        FAIL=$((FAIL + 1))
        return
    fi

    if echo "$RESPONSE" | grep -q "error"; then
        echo -e "  ${RED}✗ $name — RPC error: $(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -1)${NC}"
        FAIL=$((FAIL + 1))
        return
    fi

    if [ -n "$expect" ]; then
        if echo "$RESPONSE" | grep -q "$expect"; then
            echo -e "  ${GREEN}✓ $name${NC}"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}✗ $name — expected '$expect', got: $RESPONSE${NC}"
            FAIL=$((FAIL + 1))
        fi
    else
        RESULT=$(echo "$RESPONSE" | grep -o '"result":"[^"]*"' | sed 's/"result":"//;s/"//' || echo "$RESPONSE")
        echo -e "  ${GREEN}✓ $name — $RESULT${NC}"
        PASS=$((PASS + 1))
    fi
}

echo ""
echo "━━━ ExternEVM Health Check ━━━"
echo "  Target: $RPC_URL"
echo ""

# Check 1: Chain ID
check "Chain ID (22042004 = 0x1505594)" "eth_chainId" "" "0x1505594"

# Check 2: Block number (should be non-zero if node is producing)
check "Block number" "eth_blockNumber" ""

# Check 3: Net version
check "Network version" "net_version" ""

# Check 4: Peer count (dev mode = 0, that's fine)
check "Net peer count" "net_peerCount" ""

# Check 5: Gas price
check "Gas price" "eth_gasPrice" ""

# Check 6: Accounts (dev mode should have pre-funded accounts)
check "Accounts available" "eth_accounts" ""

# Check 7: Web3 client version
check "Client version" "web3_clientVersion" ""

# Check 8: Syncing status
check "Syncing status" "eth_syncing" ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Node has issues!${NC}"
    exit 1
else
    echo -e "  ${GREEN}Node is healthy!${NC}"
    exit 0
fi