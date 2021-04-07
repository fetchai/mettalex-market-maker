# This is a helper file to test breach functionality on Python console

from mettalex_contract_setup import connect, deploy, full_setup, deposit, earn, BalanceReporter, connect_deployed, withdraw, deploy_contract, get_contracts, whitelist_vault
# from setup_testnet_pool import get_spot_price
import os
import sys

# os.chdir('price-leveraged-token/market-maker/on-chain')
# sys.path.append(os.getcwd())

w3, admin = connect('local', 'admin')
contracts = get_contracts(w3, 3)
deployed_contracts = deploy(w3, contracts)
w3, acc, deployed_contracts = full_setup(w3, admin, deployed_contracts=deployed_contracts, price=2500)

# w3, contracts = connect_deployed()
y_vault = deployed_contracts['YVault']
coin = deployed_contracts['Coin']
ltk = deployed_contracts['Long']
stk = deployed_contracts['Short']

# Existing Flow
reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)
balancer = deployed_contracts['BPool']
strategy = deployed_contracts['PoolController']
y_controller = deployed_contracts['YController']
deposit(w3, y_vault, coin, 200000)
earn(w3, y_vault)
reporter.print_balances(y_vault.address, 'Y Vault')
reporter.print_balances(balancer.address, 'Balancer AMM')

withdraw(w3, y_vault, 11000)
mVault = deployed_contracts['Vault']

acct = w3.eth.defaultAccount

mVault.functions.isSettled().call()
mVault.functions.priceSpot().call()
mVault.functions.priceFloor().call()
mVault.functions.priceCap().call()
# #strategy.functions.supply().call()

# balancer get number of tokens
balancer.functions.getNumTokens().call()
# DeNormalized weights
balancer.functions.getDenormalizedWeight(ltk.address).call()
balancer.functions.getDenormalizedWeight(stk.address).call()
balancer.functions.getDenormalizedWeight(coin.address).call()
balancer.functions.getSpotPrice(ltk.address, coin.address).call()

mVault.functions.priceSpot().call()

mVault.functions.updateSpot(3000).transact(
    {'from': acct, 'gas': 1_000_000}
)

balancer.functions.getDenormalizedWeight(ltk.address).call()
balancer.functions.getDenormalizedWeight(stk.address).call()
balancer.functions.getDenormalizedWeight(coin.address).call()
mVault.functions.priceSpot().call()
balancer.functions.MAX_TOTAL_WEIGHT().call()

strategy.functions.updateSpotAndNormalizeWeights().transact(
    {'from': acct, 'gas': 1_000_000}
)

balancer.functions.getDenormalizedWeight(ltk.address).call()
balancer.functions.getDenormalizedWeight(stk.address).call()
balancer.functions.getDenormalizedWeight(coin.address).call()
mVault.functions.priceSpot().call()

# check handleBreach should fail if vault not breached
try:
    strategy.functions.handleBreach().transact(
        {'from': acct, 'gas': 1_000_000}
    )
except:
    print("Vault not breached")

# #strategy.functions.supply().call()

withdraw(w3, y_vault, 11000)

# #strategy.functions.supply().call()
mVault.functions.isSettled().call()
ltk.functions.totalSupply().call()
stk.functions.totalSupply().call()
#strategy.functions.supply().call()
strategy.functions.isBreachHandled().call()

# trigger breach
tx_hash = mVault.functions.updateSpot(2500000).transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

mVault.functions.isSettled().call()
ltk.functions.totalSupply().call()
stk.functions.totalSupply().call()
# #strategy.functions.supply().call()
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
#strategy.functions.supply().call()

strategy.functions.isBreachHandled().call()

tx_hash = strategy.functions.handleBreach().transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
tx_receipt.gasUsed


# should fail deposit for breached contracts
try:
    strategy.functions.deposit().transact(
        {'from': acct, 'gas': 1_000_000}
    )
except:
    print("Vault breached")

# should not fail
withdraw(w3, y_vault, 11000)

# See decreased supply after withdraw
#strategy.functions.supply().call()
strategy.functions.isBreachHandled().call()

# Deploy new vault and long and short token
contracts = get_contracts(w3)
ltk = deploy_contract(w3, contracts['Long'], 'Long Position', 'LTOK', 6, 2)
stk = deploy_contract(w3, contracts['Short'], 'Short Position', 'STOK', 6, 2)
vault = deploy_contract(
    w3, contracts['Vault'],
    'Mettalex Vault', 2, coin.address, ltk.address, stk.address,
    acct, balancer.address, 3000, 2000, 1, 300
)

whitelist_vault(w3, vault, ltk, stk)
tx_hash = vault.functions.updateSpot(2500).transact(
    {'from': acct, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

strategy.functions.longToken().call()
strategy.functions.shortToken().call()
strategy.functions.mettalexVault().call()
strategy.functions.isBreachHandled().call()

tx_hash = strategy.functions.updateCommodityAfterBreach(vault.address, ltk.address, stk.address).transact(
    {'from': acct, 'gas': 1_000_000}
)

tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

strategy.functions.longToken().call()
strategy.functions.shortToken().call()
strategy.functions.mettalexVault().call()
strategy.functions.isBreachHandled().call()
