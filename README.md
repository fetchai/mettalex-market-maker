# Mettalex DEX
The Mettalex Decentralised Exchange (DEX) consists of several distinct layers:

* liquidity provision - this makes use of [audited contracts from the yearn ecosystem](https://github.com/iearn-finance/yearn-audits)
* decentralised exchange - this makes use of [audited contracts from the Balancer ecosystem](https://docs.balancer.finance/protocol/security/audits) together with a [Mettalex Pool Controller](on-chain/pool-controller/contracts/StrategyBalancerMettalexV2.sol) acting as a smart pool
* [Mettalex vault](on-chain/mettalex-vault/contracts/vault/Vault.sol) - this stores the collateral acting backing the position tokens 

The [Mettalex vault](on-chain/mettalex-vault/contracts/vault/Vault.sol) allows traders and market makers to mint pairs of long and short position tokens by locking collateral.  It also allows redemption of a long and short pair for the underlying collateral.

The on-chain market maker allows traders to enter/exit a single-sided position without going through
the "mint pair and sell one side" flow.

The market maker itself is a  [Mettalex Pool Controller](on-chain/pool-controller/contracts/StrategyBalancerMettalexV2.sol) contract 
that makes use of a private [Balancer](https://balancer.finance) pool internally
to set position token prices in line with the underlying asset price.


![Mettalex Outline](mettalex_diagram_outlines_v9p3_white.png "Mettalex Outline")
