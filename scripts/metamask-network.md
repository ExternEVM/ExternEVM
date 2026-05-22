# MetaMask Network Configuration — ExternEVM

## Local Development

| Field           | Value                      |
|----------------|----------------------------|
| Network Name   | ExternEVM Local            |
| RPC URL        | http://127.0.0.1:8545      |
| Chain ID       | 22042004                   |
| Currency Symbol| XETH                       |
| Block Explorer | (leave empty)              |

## Remote Access via Cloudflare Tunnel

| Field           | Value                              |
|----------------|------------------------------------|
| Network Name   | ExternEVM Testnet                  |
| RPC URL        | https://<your-tunnel-url>.trycloudflare.com |
| Chain ID       | 22042004                           |
| Currency Symbol| XETH                               |
| Block Explorer | (leave empty)                      |

### How to get the tunnel URL:

1. Start your ExternEVM node locally (native or Docker)
2. Run `./scripts/deploy-tunnel.sh`
3. Copy the `https://xxx.trycloudflare.com` URL from the output
4. Use that URL as the RPC URL in MetaMask

### Import a pre-funded dev account:

1. Open MetaMask → Import Account
2. Paste private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
3. This is the standard dev account with pre-funded XETH

### Notes:

- Quick tunnel URLs change every restart. Share the new URL with users each time.
- For a stable URL, use a named tunnel: `./scripts/deploy-tunnel.sh --name externevm`
  (requires a free Cloudflare account + `cloudflared tunnel login`)
- Your machine must stay running and online for others to access the node.
- The tunnel provides HTTPS automatically — MetaMask works without warnings.