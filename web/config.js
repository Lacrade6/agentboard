// AgentBoard deployment config.
// Testnet addresses are filled in after the BSC testnet deploy.
// For MAINNET: agentBoard = the deployed AgentBoard address,
// agentId = 0x60b9262456de011f7d15a54cdd8c48baaa8b022f (real SPACE ID Agent ID),
// chainId = 56, rpcUrl = https://bsc-dataseed.bnbchain.org,
// explorer = https://bscscan.com
window.AGENTBOARD_CONFIG = {
  chainId: 97,
  chainName: "BNB Smart Chain Testnet",
  rpcUrl: "https://data-seed-prebsc-1-s1.bnbchain.org:8545", // first entry of rpcUrls (kept for compat)
  // Tried in order; the first one that answers with the right chainId wins.
  // data-seed-prebsc-1 timed out / refused connections from some networks
  // (2026-11-19: site showed "Could not load tasks" until a fallback was added).
  rpcUrls: [
    "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
    "https://bsc-testnet-rpc.publicnode.com",
    "https://data-seed-prebsc-2-s1.bnbchain.org:8545",
  ],
  explorer: "https://testnet.bscscan.com",
  agentBoard: "0x70dfca893f832D7B957681AF8aFb15ac2ACF15E1", // TODO: fill after testnet deploy
  agentId: "0x407c4d2B7F635E2cE796a71b189c31Cb59445940", // mock Agent ID on testnet
};
