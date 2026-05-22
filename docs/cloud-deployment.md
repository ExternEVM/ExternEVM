 ExternEVM Cloud Deployment Guide

## Overview

This guide covers exposing your local ExternEVM node to the internet using
a Cloudflare Tunnel. No VPS, no server, no domain purchase needed — your
laptop becomes the server.

**Architecture:**
Users (MetaMask / Remix / cast)
↓ HTTPS
Cloudflare Edge Network
↓ encrypted tunnel
Your laptop / desktop
↓ localhost
Docker container (or native Reth)
↓
Modified Reth with API_CALL precompile
↓
Outbound HTTP to external APIs

## Quick Start (5 commands)

```bash
# 1. Start your ExternEVM node
docker compose up --build -d

# 2. Verify it's running
./scripts/health-check.sh

# 3. Start the tunnel
./scripts/deploy-tunnel.sh

# 4. Share the tunnel URL with users
#    They add it as RPC URL in MetaMask with Chain ID 22042004

# 5. Test from another machine
curl -X POST https://<tunnel-url>.trycloudflare.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

## Detailed Setup

### Prerequisites

- Docker and Docker Compose installed
- ExternEVM repo cloned with submodules:
```bash
  git clone --recurse-submodules https://github.com/prateushsharma/ExternEVM.git
  cd ExternEVM
```
- Node built and verified locally (Milestones 1–5 complete)

### Step 1: Start the node

**Option A — Docker (recommended):**

```bash
docker compose up --build -d
docker compose logs -f  # watch logs, Ctrl+C to detach
```

**Option B — Native:**

```bash
cd reth
cargo run --release -p reth -- node \
  --dev \
  --chain ../config/genesis.json \
  --http \
  --http.api eth,net,web3 \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.corsdomain "*"
```

### Step 2: Verify the node

```bash
chmod +x scripts/health-check.sh
./scripts/health-check.sh
```

You should see all checks passing with Chain ID 22042004.

### Step 3: Start the Cloudflare Tunnel

```bash
chmod +x scripts/deploy-tunnel.sh
./scripts/deploy-tunnel.sh
```

The script will:
1. Install `cloudflared` if not present (Linux/macOS)
2. Check that your node is running
3. Start a tunnel and print the public URL

**The URL looks like:** `https://something-random.trycloudflare.com`

### Step 4: Share with users

Send users these instructions:

1. Open MetaMask → Add Network → Add Manually
2. Fill in:
   - **Network Name:** ExternEVM Testnet
   - **RPC URL:** `https://<your-tunnel-url>.trycloudflare.com`
   - **Chain ID:** `22042004`
   - **Currency Symbol:** `XETH`
3. Import the dev private key to get pre-funded XETH:
   `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
4. Open Remix, set environment to "Injected Provider - MetaMask"
5. Deploy and interact with ExternApiDemo.sol

### Step 5: Verify remote access

From any other machine:

```bash
# Check chain ID
curl -X POST https://<tunnel-url>.trycloudflare.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x150a5a4"}

# Call a deployed contract
cast call <CONTRACT_ADDR> "getBitcoinPrice()(uint256)" \
  --rpc-url https://<tunnel-url>.trycloudflare.com
```

## Stable URL with Named Tunnel

Quick tunnels give a random URL that changes on restart. For a stable URL:

### One-time setup:

```bash
# 1. Create a free Cloudflare account at https://dash.cloudflare.com
# 2. Login from CLI
cloudflared tunnel login

# 3. Start with a name
./scripts/deploy-tunnel.sh --name externevm
```

The named tunnel gives you a consistent URL. You can also attach a custom
domain if you add one to Cloudflare.

## Production Hardening

For a more serious deployment, set the PRODUCTION environment variable
to restrict RPC methods:

```bash
# In docker-compose.yml, add:
environment:
  PRODUCTION: "true"
```

This disables `debug` and `trace` RPC methods which can leak internal
state or be used for DoS attacks.

## Limitations

- **Uptime = your machine's uptime.** If your laptop sleeps or disconnects,
  the node goes offline. For 24/7 availability, deploy to a VPS (see below).
- **Quick tunnel URLs are ephemeral.** They change every time you restart
  the tunnel. Users need the new URL each time.
- **Single node.** ExternEVM v0 is intentionally single-node. There is no
  block finality guarantee, no validator set, no consensus.
- **Dev mode.** The node runs with `--dev` which auto-mines blocks on
  transactions. There is no real PoS/PoW.

## Future: VPS Deployment

For 24/7 availability, deploy to a VPS:

- **Oracle Cloud Free Tier** — Ampere A1 (4 OCPU, 24GB RAM). Free forever.
  Enough to compile Reth on-server.
- **Any cheap VPS** — Use the pre-built Docker image from GHCR (Milestone 6b)
  so the server never compiles Rust. Even a 1-2GB RAM server works.

VPS deployment scripts will be added in a future milestone.

## Troubleshooting

### "cloudflared: command not found"
Install manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

### Tunnel starts but no URL appears
Wait 10-15 seconds. The URL is printed by cloudflared to stderr. If still
nothing, try running cloudflared directly:
```bash
cloudflared tunnel --url http://localhost:8545
```

### MetaMask shows "Could not fetch chain ID"
- Verify the tunnel URL is correct (copy-paste, don't type)
- Check your node is still running: `./scripts/health-check.sh`
- Check the tunnel is still active in the terminal

### "API_CALL failed" on contract calls
- The Reth node needs outbound internet access to call external APIs
- Check that the API endpoint is reachable from your machine
- Some APIs rate-limit; wait and retry

### Docker build fails with OOM
Reth is a heavy Rust build. Ensure Docker has at least 4GB RAM allocated.
On Docker Desktop: Settings → Resources → Memory → 8 GB recommended.