# This is a helper file to test breach functionality on Python console
from mettalex_contract_setup import connect, deploy, get_contracts, full_setup, deposit, earn, upgrade_strategy, BalanceReporter, connect_deployed, withdraw, connect_strategy, deploy_contract, get_contracts, whitelist_vault

# setup
w3, admin = connect('local', 'admin')
contracts = get_contracts(w3)
deployed_contracts = deploy(w3, contracts)
w3, acc, deployed_contracts = full_setup(w3, admin, deployed_contracts=deployed_contracts, price=2500000)

coin = deployed_contracts['Coin']
ltk = deployed_contracts['Long']
stk = deployed_contracts['Short']
vault = deployed_contracts['Vault']
balancer = deployed_contracts['BPool']
y_vault = deployed_contracts['YVault']
y_controller = deployed_contracts['YController']
strategy = deployed_contracts['PoolController']

# full scenario for update strategy
reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)
reporter.print_balances(admin, 'admin')

print('Initial Supply', strategy.functions.supply().call())

deposit(w3, y_vault, coin, 20000)
earn(w3, y_vault)

withdraw(w3, y_vault, 200)

print('After Withdraw Supply', strategy.functions.supply().call())
print('Is vault settled', vault.functions.isSettled().call())
print('Spot Price', vault.functions.priceSpot().call())

vault.functions.updateSpot(3000000).transact(
    {'from': acc, 'gas': 1_000_000}
)

print('Is vault settled', vault.functions.isSettled().call())

strategy.functions.updateSpotAndNormalizeWeights().transact(
    {'from': acc, 'gas': 1_000_000}
)

vault.functions.updateSpot(3000001).transact(
    {'from': acc, 'gas': 1_000_000}
)

print('Is vault settled', vault.functions.isSettled().call())
print('Is breach handled', strategy.functions.isBreachHandled().call())

# handle breach
tx_hash = strategy.functions.handleBreach().transact(
    {'from': acc, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
tx_receipt.gasUsed

print('Is vault settled', vault.functions.isSettled().call())
print('After breach ltk Supply', ltk.functions.totalSupply().call())
print('After breach stk Supply', stk.functions.totalSupply().call())

# See increased supply after breach handle
print('After breach strategy Supply', strategy.functions.supply().call())
print('Is breach handled', strategy.functions.isBreachHandled().call())

tx_hash = strategy.functions.handleBreach().transact(
    {'from': acc, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
tx_receipt.gasUsed

# Deploy new vault and long and short token
ltk = deploy_contract(w3, contracts['Long'], 'Long Position', 'LTOK', 6, 2)
stk = deploy_contract(
    w3, contracts['Short'], 'Short Position', 'STOK', 6, 2)

vault = deploy_contract(
    w3, contracts['Vault'],
    'Mettalex Vault', 2, coin.address, ltk.address, stk.address,
    acc, balancer.address, 4000000, 3000000, 100000000, 300
)

whitelist_vault(w3, vault, ltk, stk)

tx_hash = vault.functions.updateSpot(3500000).transact(
    {'from': acc, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

print('Old LTK', strategy.functions.long_token().call())
print('Old STK', strategy.functions.short_token().call())
print('Old Vault', strategy.functions.mettalex_vault().call())
print('Is breach handled', strategy.functions.isBreachHandled().call())

tx_hash = strategy.functions.updateCommodityAfterBreach(vault.address, ltk.address, stk.address).transact(
    {'from': acc, 'gas': 1_000_000}
)
tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

print('New LTK', strategy.functions.long_token().call())
print('New STK', strategy.functions.short_token().call())
print('New Vault', strategy.functions.mettalex_vault().call())
print('Is breach handled', strategy.functions.isBreachHandled().call())

print('Initial Supply', strategy.functions.supply().call())

deposit(w3, y_vault, coin, 20000)
earn(w3, y_vault)

print('After Withdraw Supply', strategy.functions.supply().call())

withdraw(w3, y_vault, 200)
withdraw(w3, y_vault, 2000)

print('After Withdraw Supply', strategy.functions.supply().call())
print('Is vault settled', vault.functions.isSettled().call())
print('Spot Price', vault.functions.priceSpot().call())

# update strategy
strategy = upgrade_strategy(w3, contracts, strategy,
                            y_controller, coin, balancer, vault, ltk, stk)

print('Initial Supply', strategy.functions.supply().call())

deposit(w3, y_vault, coin, 20000)
earn(w3, y_vault)

print('After Withdraw Supply', strategy.functions.supply().call())
print('mxUSDT supply', y_vault.functions.balanceOf(acc).call()/10**18)

withdraw(w3, y_vault, 20000)

print('mxUSDT supply', y_vault.functions.balanceOf(acc).call())
print('After Withdraw Supply', strategy.functions.supply().call())
print('Is vault settled', vault.functions.isSettled().call())
print('Spot Price', vault.functions.priceSpot().call())
