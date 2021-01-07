# Mettalex Pool Controller

Controller for non-finalized Balancer pool AMM that updates weights in response to underlying asset price change.

Starting with [StrategyBalancerMTA](https://etherscan.io/address/0x15f8afe8e14a91814808fb14cdf25feca4bd835a#code) as a starting point but then modified to interact with a non-finalised pool and price updates.
It contains a mix of stablecoins in addition to  L and S tokens. The liquidity contained in the AMM pool is for traders to swap between each other (i.e. Exchange Layer).


## To run the tests:

* Please setup .env (PORT=8586) before running tests for the port to run tests on

> cd on-chain/pool-controller

> npm install

> ganache-cli --deterministic (run in a seperate terminal)

> npm run test