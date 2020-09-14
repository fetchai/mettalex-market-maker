# This is a helper file to test breach functionality on Python console

from setup_contracts import full_setup, deposit, earn, BalanceReporter, connect_deployed, withdraw, connect_strategy, deploy_contract, get_contracts, whitelist_vault
import os
import sys

os.chdir('price-leveraged-token/market-maker/on-chain')
sys.path.append(os.getcwd())

w3, contracts = connect_deployed()
y_vault = contracts['YVault']
coin = contracts['Coin']
ltk = contracts['Long']
stk = contracts['Short']

# Existing Flow
reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)
balancer = contracts['BPool']
strategy = contracts['PoolController']
y_controller = contracts['YController']
deposit(w3, y_vault, coin, 200000)
earn(w3, y_vault)
reporter.print_balances(y_vault.address, 'Y Vault')
reporter.print_balances(balancer.address, 'Balancer AMM')

withdraw(w3, y_vault, 11000)
mVault = contracts['Vault']

# update address returned by: python3 setup_contracts.py -a deploy
strategy = connect_strategy(w3, '0x9b1f7F645351AF3631a656421eD2e40f2802E6c0')
acct = w3.eth.defaultAccount

mVault.functions.isSettled().call()
mVault.functions.priceSpot().call()
mVault.functions.priceFloor().call()
mVault.functions.priceCap().call()
strategy.functions.supply().call()

# check handleBreach should fail if vault not breached
strategy.functions.handleBreach().transact(
    {'from': acct, 'gas': 1_000_000}
)

strategy.functions.supply().call()

strategy.functions.deposit().transact(
    {'from': acct, 'gas': 1_000_000}
)
strategy.functions.supply().call()

withdraw(w3, y_vault, 11000)

strategy.functions.supply().call()
mVault.functions.isSettled().call()
ltk.functions.totalSupply().call()
stk.functions.totalSupply().call()
strategy.functions.supply().call()
strategy.functions.isBreachHandled().call()

# trigger breach
tx_hash = mVault.functions.updateSpot(3000001).transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

mVault.functions.isSettled().call()
ltk.functions.totalSupply().call()
stk.functions.totalSupply().call()
strategy.functions.supply().call()
strategy.functions.isBreachHandled().call()

# handle breach
tx_hash = strategy.functions.handleBreach().transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
tx_receipt.gasUsed

mVault.functions.isSettled().call()
ltk.functions.totalSupply().call()
stk.functions.totalSupply().call()
# See increased supply after breach handle
strategy.functions.supply().call()

strategy.functions.isBreachHandled().call()

tx_hash = strategy.functions.handleBreach().transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
tx_receipt.gasUsed


# should fail deposit for breached contracts
strategy.functions.deposit().transact(
    {'from': acct, 'gas': 1_000_000}
)

# should not fail
withdraw(w3, y_vault, 11000)

# See decreased supply after withdraw
strategy.functions.supply().call()
strategy.functions.isBreachHandled().call()

# Deploy new vault and long and short token
contracts = get_contracts(w3)
ltk = deploy_contract(w3, contracts['Long'], 'Long Position', 'LTOK', 6, 2)
stk = deploy_contract(w3, contracts['Short'], 'Short Position', 'STOK', 6, 2)
vault = deploy_contract(
    w3, contracts['Vault'],
    'Mettalex Vault', 2, coin.address, ltk.address, stk.address,
    acct, balancer.address, 4000000, 3000000, 100000000, 300
)

whitelist_vault(w3, vault, ltk, stk)
tx_hash = vault.functions.updateSpot(3500000).transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

strategy.functions.long_token().call()
strategy.functions.short_token().call()
strategy.functions.mettalex_vault().call()
strategy.functions.isBreachHandled().call()

tx_hash = strategy.functions.updateCommodityAfterBreach(vault.address, ltk.address, stk.address).transact(
    {'from': acct, 'gas': 1_000_000}
)

tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

strategy.functions.long_token().call()
strategy.functions.short_token().call()
strategy.functions.mettalex_vault().call()
strategy.functions.isBreachHandled().call()
