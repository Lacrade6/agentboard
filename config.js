// AgentBoard deployment config — MAINNET (live).
// Deployed 19 Nov 2026: AgentBoard 0x980FC3EB9D8b64992AB3218e6232c0348ff5041f
// (deploy tx 0x48e0fefd608bfbc8e3cbc3fc91aeabd484a2827c59f3875fa89b71dc11813d3b).
// Testnet was: chainId 97, board 0x70dfca893f832D7B957681AF8aFb15ac2ACF15E1,
// mock Agent ID 0x407c4d2B7F635E2cE796a71b189c31Cb59445940.
window.AGENTBOARD_CONFIG = {
  chainId: 56,
  chainName: "BNB Smart Chain",
  rpcUrl: "https://bsc-dataseed.bnbchain.org", // first entry of rpcUrls (kept for compat)
  // Tried in order; the first one that answers with the right chainId wins.
  rpcUrls: [
    "https://bsc-dataseed.bnbchain.org",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc-dataseed1.ninicoin.io",
  ],
  explorer: "https://bscscan.com",
  agentBoard: "0x980FC3EB9D8b64992AB3218e6232c0348ff5041f",
  agentId: "0x60b9262456de011f7d15a54cdd8c48baaa8b022f", // real SPACE ID Agent ID
};
