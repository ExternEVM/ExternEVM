#!/bin/bash
set -e

# ============================================================
# ExternEVM — Cloudflare Tunnel Deployment
# Exposes your local ExternEVM node to the internet via HTTPS
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║         ExternEVM Tunnel Deployment          ║"
    echo "║   Expose your local node to the internet     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

install_cloudflared() {
    echo -e "${YELLOW}[1/4] Installing cloudflared...${NC}"

    if check_command cloudflared; then
        echo -e "${GREEN}  ✓ cloudflared already installed$(cloudflared --version 2>&1 | head -1)${NC}"
        return
    fi

    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)
            case "$ARCH" in
                x86_64)
                    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
                    ;;
                aarch64|arm64)
                    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
                    ;;
                *)
                    echo -e "${RED}Unsupported architecture: $ARCH${NC}"
                    exit 1
                    ;;
            esac

            echo "  Downloading cloudflared..."
            curl -fsSL "$CLOUDFLARED_URL" -o /tmp/cloudflared.deb
            sudo dpkg -i /tmp/cloudflared.deb
            rm /tmp/cloudflared.deb
            ;;
        Darwin)
            if check_command brew; then
                brew install cloudflared
            else
                echo -e "${RED}Install Homebrew first: https://brew.sh${NC}"
                exit 1
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo -e "${YELLOW}  Windows detected. Install cloudflared manually:${NC}"
            echo "  https://github.com/cloudflare/cloudflared/releases/latest"
            echo "  Or: winget install cloudflare.cloudflared"
            exit 1
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac

    if check_command cloudflared; then
        echo -e "${GREEN}  ✓ cloudflared installed successfully${NC}"
    else
        echo -e "${RED}  ✗ cloudflared installation failed${NC}"
        exit 1
    fi
}

check_node_running() {
    echo -e "${YELLOW}[2/4] Checking if ExternEVM node is running...${NC}"

    local RPC_URL="${1:-http://127.0.0.1:8545}"

    # Try up to 5 times with 2s delay
    for i in $(seq 1 5); do
        RESPONSE=$(curl -s -X POST "$RPC_URL" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null || true)

        if echo "$RESPONSE" | grep -q "0x1505594"; then
            echo -e "${GREEN}  ✓ ExternEVM node is running (Chain ID: 22042004)${NC}"
            return 0
        fi

        if [ "$i" -lt 5 ]; then
            echo "  Attempt $i/5 — node not ready, retrying in 2s..."
            sleep 2
        fi
    done

    echo -e "${RED}  ✗ ExternEVM node is not running on $RPC_URL${NC}"
    echo ""
    echo "  Start your node first:"
    echo "    Option A (native):  cd reth && cargo run --release -p reth -- node --dev --chain ../config/genesis.json --http --http.api eth,net,web3 --http.addr 0.0.0.0 --http.port 8545 --http.corsdomain '*'"
    echo "    Option B (docker):  docker compose up --build -d"
    echo ""
    exit 1
}

start_tunnel() {
    local RPC_PORT="${1:-8545}"
    local MODE="${2:-quick}"

    echo -e "${YELLOW}[3/4] Starting Cloudflare Tunnel...${NC}"

    if [ "$MODE" = "named" ] && [ -n "$TUNNEL_NAME" ]; then
        # Named tunnel mode — requires cloudflare login
        echo "  Starting named tunnel: $TUNNEL_NAME"
        echo "  This requires a Cloudflare account. Run 'cloudflared tunnel login' first."
        cloudflared tunnel --url "http://127.0.0.1:$RPC_PORT" --name "$TUNNEL_NAME" &
        TUNNEL_PID=$!
    else
        # Quick tunnel — no account needed
        echo "  Starting quick tunnel (no account needed)..."
        echo "  The tunnel URL will appear below."
        echo ""

        # cloudflared prints the URL to stderr, capture it
        cloudflared tunnel --url "http://127.0.0.1:$RPC_PORT" 2>&1 &
        TUNNEL_PID=$!
    fi

    # Wait for tunnel to establish and extract URL
    echo "  Waiting for tunnel to establish..."
    sleep 5

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            TUNNEL IS RUNNING                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Look above for your tunnel URL — it looks like:${NC}"
    echo -e "  ${CYAN}https://something-random.trycloudflare.com${NC}"
    echo ""
}

print_instructions() {
    echo -e "${YELLOW}[4/4] Setup instructions${NC}"
    echo ""
    echo -e "${CYAN}━━━ MetaMask Configuration ━━━${NC}"
    echo "  Network Name:    ExternEVM Testnet"
    echo "  RPC URL:         <your-tunnel-url-from-above>"
    echo "  Chain ID:        22042004"
    echo "  Currency Symbol: XETH"
    echo "  Block Explorer:  (leave empty)"
    echo ""
    echo -e "${CYAN}━━━ Test from another machine ━━━${NC}"
    echo '  curl -X POST <your-tunnel-url> \'
    echo '    -H "Content-Type: application/json" \'
    echo '    -d '\''{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'\'''
    echo ""
    echo -e "${CYAN}━━━ Test with cast ━━━${NC}"
    echo '  cast call <CONTRACT_ADDR> "getBitcoinPrice()(uint256)" --rpc-url <your-tunnel-url>'
    echo ""
    echo -e "${CYAN}━━━ Stop the tunnel ━━━${NC}"
    echo "  Press Ctrl+C or kill this process"
    echo ""
    echo -e "${YELLOW}⚠  Your laptop must stay running and connected to the internet.${NC}"
    echo -e "${YELLOW}⚠  Quick tunnel URL changes on restart. For a stable URL, use a named tunnel.${NC}"
    echo ""
}

cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down tunnel...${NC}"
    if [ -n "$TUNNEL_PID" ]; then
        kill "$TUNNEL_PID" 2>/dev/null || true
        wait "$TUNNEL_PID" 2>/dev/null || true
    fi
    echo -e "${GREEN}Tunnel stopped.${NC}"
    exit 0
}

# ============================================================
# Main
# ============================================================

print_banner

RPC_PORT="${RPC_PORT:-8545}"
TUNNEL_NAME="${TUNNEL_NAME:-}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            RPC_PORT="$2"
            shift 2
            ;;
        --name)
            TUNNEL_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./deploy-tunnel.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --port PORT    RPC port (default: 8545)"
            echo "  --name NAME    Named tunnel (requires Cloudflare login)"
            echo "  --help         Show this help"
            echo ""
            echo "Examples:"
            echo "  ./deploy-tunnel.sh                     # Quick tunnel, no account"
            echo "  ./deploy-tunnel.sh --port 8545         # Specify port"
            echo "  ./deploy-tunnel.sh --name externevm    # Named tunnel (stable URL)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

trap cleanup SIGINT SIGTERM

install_cloudflared
check_node_running "http://127.0.0.1:$RPC_PORT"

if [ -n "$TUNNEL_NAME" ]; then
    start_tunnel "$RPC_PORT" "named"
else
    start_tunnel "$RPC_PORT" "quick"
fi

print_instructions

# Keep running until Ctrl+C
echo -e "${GREEN}Tunnel is active. Press Ctrl+C to stop.${NC}"
wait "$TUNNEL_PID"