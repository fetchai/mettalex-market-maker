module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 6000000,
      gasPrice: 5e9,
      networkId: '*',
    },
  },
};
