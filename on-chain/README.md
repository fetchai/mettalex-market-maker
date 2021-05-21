# Autonomous Market Maker System
This directory contains copies of Mettalex system contracts for use in development
and testing of autonomous market maker functionality.  The definitive versions of
these contracts should be used for further development and the contracts under this
subdirectory updated.  

MMcD 2020-08-12: With better devops and git-fu this could probably be done with separate
branches and appropriate CI/CD setup however that is a refinement for later.

# Components

## Core Components
* mettalex-vault: Vault and position tokens for storing coin and minting/redeeming positions 
  * mettalex-protocol directory contains these as separate protocol for unit testing, mettalex-vault is used in full system
    build process
* **pool-controller**: (key component) controller for non-finalized Balancer pool AMM that 
  updates weights in response to underlying asset price change.  
  Originally based on  [StrategyBalancerMTA](https://etherscan.io/address/0x15f8afe8e14a91814808fb14cdf25feca4bd835a#code) as
  a starting point but then modify to interact with a non-finalised pool and price updates.
  Current version implements dynamic Balancer pool weights to keep sum of position token prices
  equal to underlying collateral value as described in 
  [Mettalex Autonomous Market Maker Mathematics](https://medium.com/mettalex/mettalex-autonomous-market-maker-mathematics-f28470d188d6)

## Reused Existing DeFi Components 
* mettalex-yearn: copy of yearn [yVault](https://etherscan.io/address/0x5dbcf33d8c2e976c6b560249878e6f1491bca25c#code)
  and [Controller](https://etherscan.io/address/0x31317f9a5e4cc1d231bdf07755c994015a96a37c#code) contracts for liquidity providers to deposit funds and for 
  those funds to be used by autonomous market maker
* mettalex-balancer: autonomous market maker factory and pool from 
  [Balancer](https://docs.balancer.finance/smart-contracts/addresses) 

## Non-Core Components
For integration with USDT (Tether) and other non-standard ERC20 tokens we need a bridge contract
to convert into standard ERC20 tokens.

* mettalex-coin: Stablecoin used for vault collateral and fees.  
  Copy of [TetherToken (USDT)](https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code)
* mettalex-bridge: Conversion between non-standard ERC20 token for USDT and ERC20 token used as coin within Mettalex.


## Getting started
Get the code from github
    
    git clone git@github.com:fetchai/mettalex-market-maker.git

Make sure Node.js and python (pip3) is already setup

To initialise project setup:

    cd on-chain/
    make init

# Local development setup
  Start a local ganache blockchain with `npx ganache-cli`

  To install ganache-cli:

      npm install -g ganache-cli

## Script setup
From this directory the `scripts/mettalex_contract_setup.py` script deploys or connect the contracts. After deployment, contract addresses are stored in contract_cache.json.


* To deploy all the contracts and get their instances, run following command:

    `$python3 mettalex_contract_setup.py -a setup -n local -v 3`

We can provide the contract addresses to `scripts/contract-cache/contract_address.json` if we want to connect the existing contracts.
If the address left blank, it will be automatically deployed by the script.
### Script options:
    -h, --help            
    show this help message and exit

    --action ACTION, -a ACTION
    Action to perform: connect, deploy (default), setup

    --network NETWORK, -n NETWORK
    For connecting to local, kovan, polygon-testnet, harmony-testnet, okexchain-testnet, avalanche-testnet or bsc-testnet network

    --strategy STRATEGY, -v STRATEGY
    For getting strategy version we want to deploy DEX for


For using strategy V2, we use 2 with `-v` option. 

### Output:

    Deploying contracts
    Whitelisting Mettalex vault to mint position tokens
    Long Position whitelist state for 0x504AD882Fa8D0f8fc8e9935aEF0307FF55F3AC75 changed from False to True
    Short Position whitelist state for 0x504AD882Fa8D0f8fc8e9935aEF0307FF55F3AC75 changed from False to True
    Setting strategy
    Tether USD strategy changed from 0x0000000000000000000000000000000000000000 to 0x86026611f7981657677305d3696F9Ba9AAD4d356
    Setting y-vault controller
    yVault added in yController
    Setting balancer controller
    Balancer controller 0x86026611f7981657677305d3696F9Ba9AAD4d356
    Setting Mettalex vault AMM
    Mettalex Vault strategy changed from 0x645c3B7282a601Cc6AA1E7dDBC61Be442FD3c947 to 0x86026611f7981657677305d3696F9Ba9AAD4d356

    Y Vault (0x4afA8FC89258a27cAD3CDCFB468457E38e6fbe5b) has 0.00 vault shares
      0.00 coin, 0.00 LTK, 0.00 STK


Or from within IPython console

    %load_ext autoreload
    %autoreload 2
    import os
    import sys
    os.chdir('price-leveraged-token/market-maker/on-chain/scripts')
    sys.path.append(os.getcwd())
    from mettalex_contract_setup import full_setup, deposit, earn, BalanceReporter, upgrade_strategy, set_price, get_spot_price, swap_amount_in, connect_deployed, withdraw
    
    w3, contracts = connect_deployed()
    y_vault = contracts['YVault']
    coin = contracts['Coin']
    ltk = contracts['Long']
    stk = contracts['Short']
    reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)
    balancer = contracts['BPool']
    strategy = contracts['PoolController']
    y_controller = contracts['YController']
    deposit(w3, y_vault, coin, 200000)
    earn(w3, y_vault)
    reporter.print_balances(y_vault.address, 'Y Vault')
    reporter.print_balances(balancer.address, 'Balancer AMM')
    withdraw(w3, y_vault, 11000)

## Script flow:

**Balancer Pool Factory and Balancer Pool**

* First, Balancer Factory is deployed by admin
* Then admin calls newBPool() function from BFactroy to create a balancer pool.

**Coin Token**

Admin deploys coin.
*NB: the USDT contract in mettalex-coin project is not a standard ERC20 hence not supported.  Currently using the CoinToken contract from mettalex-vault.*
 
**Position Tokens and Mettalex Vault**

Admin deploys position tokens (Long token and Short token) and vault

* To allow the minting for position tokens, admin whitelists Mettalex Vault to long and short tokens
 
**Liquidity pool**

To setup liquity pool for the providers
* Admin deploys Controller 
* Admin deploys yVault
* Set the controller in yVault contract

Admin deploys Balancer pool controller

**Strategy**
    
* Admin deploys StrategyBalancerMettalex contract

For full and final setup, following trasnactions are performed:
* Strategy address is added to the controller contract.
* To connect the Balancer pool, bpool controller is replaced by Strategy contract from admin account.
* To allow the AMM to mint Long and Short tokens, the autonomous market maker address is updated in Vault contract