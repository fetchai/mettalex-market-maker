require('dotenv').config()

module.exports = {
  accounts: {
    amount: 20, // Number of unlocked accounts
    ether: 1e6,
  },

  node: { // Options passed directly to Ganache client
    fork: "http://127.0.0.1:8545",
    port: process.env.PORT,
    deterministic: true,
    mnemonic: "myth like bonus scare over problem client lizard pioneer submit female collect",
    unlocked_accounts: ['0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1','0x19d877FdafB920ee8B1d69Ae281b82D11efD86D3','0xAe7e98b80d7448286fE2D21cF4Ded9353C0Ad96d','0x8eAB569Eeb6cE03578b0c74C3e614713e9e0f181','0xd2abAD0eFFC9f727227164a29D02B98cAedcFA91','0xbE64511891D85C2e9Cb1e5DF8421873DaFB31876','0xF5a79B729E0358C06BD859B16C67F55fBF36Ac97','0x23b52e8F9CA92Af2A463cd71cA6946BA3cd8907F','0xDdFFf9E79B9630631F2bb0483dAd818433e6141f','0x2F34009D8322a62A7A35a6B8e996473A463Bf188','0x150bD80C28681b221F509593fcEf93A0258637d9'],  
  },
};