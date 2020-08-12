# Autonomous Market Maker System
This directory contains copies of Mettalex system contracts for use in development
and testing of autonomous market maker functionality.  The definitive versions of
these contracts should be used for further development and the contracts under this
subdirectory updated.  

MMcD 2020-08-12: With better devops and git-fu this could probably be done with separate
branches and appropriate CI/CD setup however that is a refinement for later.

# Components
* mettalex-coin: Stablecoin used for vault collateral and fees.  
  Copy of [TetherToken (USDT)](https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code)
* mettalex-vault: Vault and position tokens for storing coin and minting/redeeming positions 
* mettalex-yearn: copy of yearn [yVault](https://etherscan.io/address/0x5dbcf33d8c2e976c6b560249878e6f1491bca25c#code)
  and [Controller](https://etherscan.io/address/0x31317f9a5e4cc1d231bdf07755c994015a96a37c#code) contracts for liquidity providers to deposit funds and for 
  those funds to be used by autonomous market maker
* mettalex-balancer: autonomous market maker factory and pool from 
  [Balancer](https://docs.balancer.finance/smart-contracts/addresses) 
* **pool-controller**: (key component) controller for non-finalized Balancer pool AMM that 
  updates weights in response to underlying asset price change.  
  Starting with [StrategyBalancerMTA](https://etherscan.io/address/0x15f8afe8e14a91814808fb14cdf25feca4bd835a#code) as
  a starting point but then modify to interact with a non-finalised pool and price updates.

