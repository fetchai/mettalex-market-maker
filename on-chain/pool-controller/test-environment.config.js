require("dotenv").config();

module.exports = {
  accounts: {
    amount: 20, // Number of unlocked accounts
    ether: 1e6
  },

  node: {
    // Options passed directly to Ganache client
    fork: "http://127.0.0.1:8545",
    port: process.env.PORT,
    mnemonic: "myth like bonus scare over problem client lizard pioneer submit female collect",
    unlocked_accounts: [
      "0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7",
      "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1",
      "0xFFcf8FDEE72ac11b5c542428B35EEF5769C409f0",
      "0x22d491Bde2303f2f43325b2108D26f1eAbA1e32b",
      "0xE11BA2b4D45Eaed5996Cd0823791E0C93114882d",
      "0xd03ea8624C8C5987235048901fB614fDcA89b117",
      "0x95cED938F7991cd0dFcb48F0a06a40FA1aF46EBC",
      "0x3E5e9111Ae8eB78Fe1CC3bb8915d5D461F3Ef9A9",
      "0x28a8746e75304c0780E011BEd21C72cD78cd535E",
      "0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E",
      "0x1dF62f291b2E969fB0849d99D9Ce41e2F137006e"
    ]
  }
};
