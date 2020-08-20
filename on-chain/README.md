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


# Deploying for local development
Start a local ganache blockchain with `npx ganache-cli --determinisitic` to create
a set of accounts:

    
    Available Accounts
    ==================
    (0) 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 (100 ETH)
    (1) 0xFFcf8FDEE72ac11b5c542428B35EEF5769C409f0 (100 ETH)
    (2) 0x22d491Bde2303f2f43325b2108D26f1eAbA1e32b (100 ETH)
    (3) 0xE11BA2b4D45Eaed5996Cd0823791E0C93114882d (100 ETH)
    (4) 0xd03ea8624C8C5987235048901fB614fDcA89b117 (100 ETH)
    (5) 0x95cED938F7991cd0dFcb48F0a06a40FA1aF46EBC (100 ETH)
    (6) 0x3E5e9111Ae8eB78Fe1CC3bb8915d5D461F3Ef9A9 (100 ETH)
    (7) 0x28a8746e75304c0780E011BEd21C72cD78cd535E (100 ETH)
    (8) 0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E (100 ETH)
    (9) 0x1dF62f291b2E969fB0849d99D9Ce41e2F137006e (100 ETH)
    
    Private Keys
    ==================
    (0) 0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d
    (1) 0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1
    (2) 0x6370fd033278c143179d81c5526140625662b8daa446c22ee2d73db3707e620c
    (3) 0x646f1ce2fdad0e6deeeb5c7e8e5543bdde65e86029e2fd9fc169899c440a7913
    (4) 0xadd53f9a7e588d003326d1cbf9e4a43c061aadd9bc938c843a79e7b4fd2ad743
    (5) 0x395df67f0c2d2d9fe1ad08d1bc8b6627011959b79c53d7dd6a3536a33ab8a4fd
    (6) 0xe485d098507f54e7733a205420dfddbe58db035fa577fc294ebd14db90767a52
    (7) 0xa453611d9419d0e56f499079478fd72c37b251a94bfde4d19872c44cf65386e3
    (8) 0x829e924fdf021ba3dbbc4225edfece9aca04b929d6e75613329ca6f1d31c0bb4
    (9) 0xb0057716d5917badaf911b193b12b910811c1497b5bada8d7711f758981c3773
    
    HD Wallet
    ==================
    Mnemonic:      myth like bonus scare over problem client lizard pioneer submit female collect
    Base HD Path:  m/44'/60'/0'/0/{account_index}
    

## Python setup
From this directory the `setup_contracts.py` script will deploy and connect the contracts.
Once contracts have been deployed the Makefile in `pool-controller` subdirectory
can be used to upgrade the strategy contract for development.

    (feature-token) >> python setup_contracts.py --help
    usage: Mettalex System Setup [-h] [--action ACTION] [--quantity QTY]
    
    optional arguments:
      -h, --help            show this help message and exit
      --action ACTION, -a ACTION
                            Action to perform: deposit, earn, connect_balancer,
                            deploy (default)
      --quantity QTY, -q QTY
                            Quantity of collateral tokens to transfer (scaled)

    (feature-token) >> python setup_contracts.py -a deploy
    Long Position whitelist state for 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb changed from False to True
    Short Position whitelist state for 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb changed from False to True
    Tether USD strategy changed from 0x0000000000000000000000000000000000000000 to 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0
    Balancer controller 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0
    Mettalex Vault strategy changed from 0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78 to 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0
    Mettalex Vault spot changed from 0 to 2500000
    (feature-token) >> python setup_contracts.py -a deposit -q 20000
    (feature-token) >> python setup_contracts.py -a earn


## Addresses
Admin deploys Balancer Pool Factory and creates Balancer Pool
* Account 0 deploys Balancer Pool Factory to `0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab`
* Account 0 calls newBPool to create BPool at `0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78`

Admin deploys coin 
NB: the USDT contract in mettalex-coin project doesn't seem to work in the end to end flow, failing
at the mintPositions step.  Currently using the CoinToken contract from mettalex-vault.
* Account 0 deploys USDT to `0xCfEB869F69431e42cdB54A4F4f105C19C080A601`
* Account 0 deploys Mettalx CoinToken (USDT) to `0xCfEB869F69431e42cdB54A4F4f105C19C080A601`
 
Admin deploys position tokens and vault
* Account 0 deploys Mettalex long position token to `0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B`
* Account 0 deploys Mettalex short positon token to `0xC89Ce4735882C9F0f0FE26686c53074E09B0D550`
* Account 0 deploys Mettalex Vault to `0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb`
* Account 0 whitelists Mettalex Vault to mint long and short tokens
 
Admin deploys liquidity pool
* Account 0 deploys Controller to `0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7`
* Account 0 deploys yVault to `0xe982E462b094850F12AF94d21D470e21bE9D0E9C`

Admin deploys Balancer pool controller

    Deprecated: Account 0 deploys StrategyBalancerMettalex to `0x59d3631c86BbE35EF041872d502F218A39FBa150`~~
* Account 0 deploys upgradeable StrategyBalancerMettalex to`0x9b1f7F645351AF3631a656421eD2e40f2802E6c0`

Admin connects Balancer pool controller to the liquidity pool vault controller
* Account 0 calls 