# This is a helper file to test breach functionality on Python console
from deploy_contracts import connect, deploy, get_contracts, mintPositionTokens, swap, full_setup, deposit, earn, upgrade_strategy, BalanceReporter, connect_deployed, withdraw, connect_strategy, deploy_contract, get_contracts, whitelist_vault, get_balance

# setup
w3, admin = connect('local', 'admin')
contracts = get_contracts(w3)
deployed_contracts = deploy(w3, contracts)
w3, acc, deployed_contracts = full_setup(w3, admin, deployed_contracts=deployed_contracts, price=2500)

coin = deployed_contracts['Coin']
ltk = deployed_contracts['Long']
stk = deployed_contracts['Short']
vault = deployed_contracts['Vault']
bpool = deployed_contracts['BPool']
y_vault = deployed_contracts['YVault']
y_controller = deployed_contracts['YController']
strategy = deployed_contracts['PoolController']

#Bind tokens to BPool
deposit(w3, y_vault, coin, 10000000)
earn(w3, y_vault)

mintPositionTokens(w3, vault, coin, 100000000, admin)


#initial Pool Balance:
print('Initial Pool Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')

print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')



# Swap Coin to Positions
swap(w3, strategy, coin, 1000000000, stk, 1)
print('Pool Balance after Coin to Short swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')



swap(w3, strategy, coin, 1000000000, ltk, 1)
print('Pool Balance after Coin to Long swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')



# Swap Positions to Coin
swap(w3, strategy, stk, 100000, coin, 1)
print('Pool Balance after Short to Coin swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')

swap(w3, strategy, ltk, 100000, coin, 1)
print('Pool Balance after Long to Coin swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')



# Swap Position to Position

### Swap works for 10,000 or more STK/LTK

swap(w3, strategy, ltk, 1000000000, stk, 1)
print('Pool Balance after Long to Short swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')

swap(w3, strategy, stk, 1000000000, ltk, 1)
print('Pool Balance after Short to Long swap:')
stk_balance, ltk_balance, coin_balance = get_balance(bpool.address, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')
print('User Balance:')
stk_balance, ltk_balance, coin_balance = get_balance(admin, coin, ltk, stk)
print(f'Coin: {coin_balance}, Long: {ltk_balance} and Short: {stk_balance} \n')