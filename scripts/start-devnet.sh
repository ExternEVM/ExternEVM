#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
RETH_BIN="$ROOT/reth/target/release/reth"
CL_BIN="$ROOT/consensus/target/release/externevm-consensus"
GENESIS="$ROOT/config/genesis.json"
JWT="$ROOT/config/jwt.hex"
LOG_DIR="$ROOT/logs"
PID_FILE="$ROOT/.devnet.pids"

mkdir -p "$LOG_DIR"
> "$PID_FILE"

check_bin() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: Binary not found: $1"
    echo "Run: cd $ROOT/reth && cargo build --release"
    echo "     cd $ROOT/consensus && cargo build --release"
    exit 1
  fi
}

check_bin "$RETH_BIN"
check_bin "$CL_BIN"

echo "==> Clearing old chain data..."
rm -rf /tmp/externevm-node{1,2,3}
mkdir -p /tmp/externevm-node{1,2,3}

echo "==> Starting EL Node 1 (0xf39F...2266, port 8545)..."
EXTERNEVM_VALIDATOR_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
EXTERNEVM_PEER_WAIT_MS=300 \
  "$RETH_BIN" node \
  --chain "$GENESIS" \
  --http --http.api eth,net,web3,debug,trace,admin \
  --http.addr 0.0.0.0 --http.port 8545 \
  --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
  --authrpc.jwtsecret "$JWT" \
  --port 30303 --discovery.port 30303 --discovery.v5.port 9200 \
  --datadir /tmp/externevm-node1 \
  > "$LOG_DIR/el-node1.log" 2>&1 &
echo $! >> "$PID_FILE"
EL1_PID=$!
echo "   PID: $EL1_PID"

echo "==> Waiting for Node 1 to come up..."
for i in $(seq 1 30); do
  if curl -sf -X POST http://127.0.0.1:8545 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
    > /dev/null 2>&1; then
    echo "   Node 1 is up."
    break
  fi
  sleep 1
done

echo "==> Fetching Node 1 enode..."
NODE1_ENODE=$(curl -sf -X POST http://127.0.0.1:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['enode'])")
echo "   Enode: $NODE1_ENODE"

echo "==> Starting EL Node 2 (0x7099...79C8, port 8546)..."
EXTERNEVM_VALIDATOR_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
EXTERNEVM_PEER_WAIT_MS=300 \
  "$RETH_BIN" node \
  --chain "$GENESIS" \
  --http --http.api eth,net,web3,debug,trace,admin \
  --http.addr 0.0.0.0 --http.port 8546 \
  --authrpc.addr 0.0.0.0 --authrpc.port 8552 \
  --authrpc.jwtsecret "$JWT" \
  --port 30304 --discovery.port 30304 --discovery.v5.port 9201 \
  --datadir /tmp/externevm-node2 \
  --trusted-peers "$NODE1_ENODE" \
  > "$LOG_DIR/el-node2.log" 2>&1 &
echo $! >> "$PID_FILE"
echo "   PID: $!"

echo "==> Starting EL Node 3 (0x3C44...3BC, port 8547)..."
EXTERNEVM_VALIDATOR_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
EXTERNEVM_PEER_WAIT_MS=300 \
  "$RETH_BIN" node \
  --chain "$GENESIS" \
  --http --http.api eth,net,web3,debug,trace,admin \
  --http.addr 0.0.0.0 --http.port 8547 \
  --authrpc.addr 0.0.0.0 --authrpc.port 8553 \
  --authrpc.jwtsecret "$JWT" \
  --port 30305 --discovery.port 30305 --discovery.v5.port 9202 \
  --datadir /tmp/externevm-node3 \
  --trusted-peers "$NODE1_ENODE" \
  > "$LOG_DIR/el-node3.log" 2>&1 &
echo $! >> "$PID_FILE"
echo "   PID: $!"

echo "==> Waiting 3s for EL nodes to peer..."
sleep 3

VALIDATORS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
ALL_AUTH="http://127.0.0.1:8551,http://127.0.0.1:8552,http://127.0.0.1:8553"

echo "==> Starting CL Node 1..."
"$CL_BIN" \
  --validator 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --validators "$VALIDATORS" \
  --el-auth-url http://127.0.0.1:8551 \
  --el-rpc-url http://127.0.0.1:8545 \
  --all-el-auth-urls "$ALL_AUTH" \
  --jwt-secret "$JWT" \
  --slot-time 5 \
  > "$LOG_DIR/cl-node1.log" 2>&1 &
echo $! >> "$PID_FILE"
echo "   PID: $!"

echo "==> Starting CL Node 2..."
"$CL_BIN" \
  --validator 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --validators "$VALIDATORS" \
  --el-auth-url http://127.0.0.1:8552 \
  --el-rpc-url http://127.0.0.1:8546 \
  --all-el-auth-urls "$ALL_AUTH" \
  --jwt-secret "$JWT" \
  --slot-time 5 \
  > "$LOG_DIR/cl-node2.log" 2>&1 &
echo $! >> "$PID_FILE"
echo "   PID: $!"

echo "==> Starting CL Node 3..."
"$CL_BIN" \
  --validator 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
  --validators "$VALIDATORS" \
  --el-auth-url http://127.0.0.1:8553 \
  --el-rpc-url http://127.0.0.1:8547 \
  --all-el-auth-urls "$ALL_AUTH" \
  --jwt-secret "$JWT" \
  --slot-time 5 \
  > "$LOG_DIR/cl-node3.log" 2>&1 &
echo $! >> "$PID_FILE"
echo "   PID: $!"

echo ""
echo "==> ExternEVM devnet started. PIDs saved to $PID_FILE"
echo "    Logs: $LOG_DIR/"
echo "    RPC endpoints:"
echo "      Node 1: http://127.0.0.1:8545"
echo "      Node 2: http://127.0.0.1:8546"
echo "      Node 3: http://127.0.0.1:8547"
echo ""
echo "    Run scripts/deploy-contract.sh to deploy ExternApiDemo"