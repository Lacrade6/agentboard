#!/usr/bin/env bash
# Deploy AgentBoard to a BNB Chain network.
# Usage:
#   RPC_URL=https://data-seed-prebsc-1-s1.bnbchain.org:8545 \
#   PRIVATE_KEY=0x... \
#   AGENT_ID=0x60b9262456de011f7d15a54cdd8c48baaa8b022f \
#   ./scripts/deploy.sh
# For TESTNET, deploy MockAgentId first and pass its address as AGENT_ID.
# Prints the deployed AgentBoard address. Never commit a real private key.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
: "${RPC_URL:?set RPC_URL}"
: "${PRIVATE_KEY:?set PRIVATE_KEY}"
: "${AGENT_ID:?set AGENT_ID (real Agent ID contract, or MockAgentId on testnet)}"
forge create contracts/AgentBoard.sol:AgentBoard \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --constructor-args "$AGENT_ID"
