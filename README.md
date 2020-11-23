# Mettalex DEX
The Mettalex Decentralised Exchange (DEX) consists of several distinct layers:

* liquidity provision - this makes use of [audited contracts from the yearn ecosystem](https://github.com/iearn-finance/yearn-audits)
* decentralised exchange - this makes use of [audited contracts from the Balancer ecosystem](https://docs.balancer.finance/protocol/security/audits) together with a [Mettalex pool-controller](on-chain/pool-controller/contracts/StrategyMettalexBalancerV2.sol) acting as a smart pool
* [Mettalex vault](on-chain/mettalex-vault/README.md) - this stores the collateral acting backing the position tokens 

The Mettalex vault allows traders and market makers to mint pairs of long and short position tokens by locking collateral.  It also allows redemption of a long and short pair for the underlying collateral.

The on-chain market maker allows traders to enter/exit a single-sided position without going through
the "mint pair and sell one side" flow.

The market maker itself is a private [Balancer](https://github.com/balancer-labs/balancer-core.git) pool
that is rebalanced to set position token prices in line with the underlying asset price.

A separate Pool Controller contract is used for supplying tokens to the Balancer pool.
