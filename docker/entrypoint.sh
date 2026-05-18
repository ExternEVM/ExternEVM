#!/bin/bash
set -e

# Graceful shutdown
trap 'echo "[ExternEVM] Caught SIGTERM, shutting down..."; kill -TERM "$PID"; wait "$PID"' SIGTERM SIGINT

DATA_DIR="${DATA_DIR:-/data}"
CHAIN_CONFIG="${CHAIN_CONFIG:-/config/genesis.json}"
HTTP_PORT="${HTTP_PORT:-8545}"
WS_PORT="${WS_PORT:-8546}"
P2P_PORT="${P2P_PORT:-30303}"

echo "[ExternEVM] Starting modified Reth node..."
echo "  Chain config: ${CHAIN_CONFIG}"
echo "  Data dir:     ${DATA_DIR}"
echo "  HTTP port:    ${HTTP_PORT}"
echo "  WS port:      ${WS_PORT}"
echo "  P2P port:     ${P2P_PORT}"

reth node \
  --dev \
  --chain "${CHAIN_CONFIG}" \
  --datadir "${DATA_DIR}" \
  --http \
  --http.api eth,net,web3,debug,trace \
  --http.addr 0.0.0.0 \
  --http.port "${HTTP_PORT}" \
  --http.corsdomain "*" \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port "${WS_PORT}" \
  --ws.origins "*" \
  --port "${P2P_PORT}" \
  &

PID=$!
wait "$PID"