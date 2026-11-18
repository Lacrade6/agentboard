// AgentBoard deployment config.
// Testnet addresses are filled in after the BSC testnet deploy.
// For MAINNET: agentBoard = the deployed AgentBoard address,
// agentId = 0x60b9262456de011f7d15a54cdd8c48baaa8b022f (real SPACE ID Agent ID),
// chainId = 56, rpcUrl = https://bsc-dataseed.bnbchain.org,
// explorer = https://bscscan.com
window.AGENTBOARD_CONFIG = {
  chainId: 97,
  chainName: "BNB Smart Chain Testnet",
  rpcUrl: "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
  explorer: "https://testnet.bscscan.com",
  agentBoard: "0x0000000000000000000000000000000000000000", // TODO: fill after testnet deploy
  agentId: "0x0000000000000000000000000000000000000000", // mock Agent ID on testnet
};
