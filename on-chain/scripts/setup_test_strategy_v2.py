from mettalex_contract_setup import connect, deploy, get_contracts, get_spot_price, update_spot_and_rebalance, mintPositionTokens, swap, full_setup, deposit, earn, upgrade_strategy, connect_deployed, withdraw, connect_strategy, deploy_contract, get_contracts, whitelist_vault, get_balance


def swap_from_coin():
    print('Coin to Short swap:')
    swap(w3, strategy, coin, 1000000000, stk, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens}\n')

    print('Coin to Long swap:')
    swap(w3, strategy, coin, 1000000000, ltk, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens}')


def swap_to_coin():
    print('Short to Coin swap:')
    swap(w3, strategy, stk, 100000, coin, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens} \n')

    print('Long to Coin swap:')
    swap(w3, strategy, ltk, 100000, coin, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens}')


# Swap works for 10,000 or more STK/LTK
def swap_positions():
    print('Long to Short swap:')
    swap(w3, strategy, ltk, 1000000000, stk, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens} \n')

    print('Short to Long swap:')
    swap(w3, strategy, stk, 1000000000, ltk, 1)
    stk_balance, ltk_balance, coin_balance = get_balance(
        bpool.address, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))
    print('Total Positions: ')
    total_position_tokens = (stk_balance + ltk_balance)
    print(f'Coin: {coin_balance} and Positions: {total_position_tokens}')


if __name__ == '__main__':
    # setup
    w3, admin = connect('local', 'admin')
    contracts = get_contracts(w3, 2)
    deployed_contracts = deploy(w3, contracts)
    w3, acc, deployed_contracts = full_setup(
        w3, admin, deployed_contracts=deployed_contracts, price=2500)

    coin = deployed_contracts['Coin']
    ltk = deployed_contracts['Long']
    stk = deployed_contracts['Short']
    vault = deployed_contracts['Vault']
    bpool = deployed_contracts['BPool']
    y_vault = deployed_contracts['YVault']
    y_controller = deployed_contracts['YController']
    strategy = deployed_contracts['PoolController']

    # Bind tokens to BPool
    deposit(w3, y_vault, coin, 10000000)
    earn(w3, y_vault)
    mintPositionTokens(w3, vault, coin, 100000000, admin)

    print('==================================\n')

    # initial Pool Balance:
    print('Initial Pool Balance:')
    get_balance(bpool.address, coin, ltk, stk)
    print('User Balance:')
    get_balance(admin, coin, ltk, stk)

    print('Spot prices: ')
    print('Long: ', get_spot_price(w3, bpool, coin, ltk, unitless=False))
    print('Short: ', get_spot_price(w3, bpool, coin, stk, unitless=False))

    print('==================================\n')

    # swaps
    swap_from_coin()
    print('User Balance:')
    get_balance(admin, coin, ltk, stk)

    print('==================================\n')

    swap_to_coin()
    print('User Balance:')
    get_balance(admin, coin, ltk, stk)

    print('==================================\n')

    swap_positions()
    print('User Balance:')
    get_balance(admin, coin, ltk, stk)

    # Rebalance tests:
    
    # 250
    update_spot_and_rebalance(w3, vault, strategy, 2500)
    # 300
    update_spot_and_rebalance(w3, vault, strategy, 3000)
    # 200
    update_spot_and_rebalance(w3, vault, strategy, 2000)
    # 200.1
    update_spot_and_rebalance(w3, vault, strategy, 2001)
    # 299
    update_spot_and_rebalance(w3, vault, strategy, 2990)
    # 299.9
    update_spot_and_rebalance(w3, vault, strategy, 2999)
    # 201
    update_spot_and_rebalance(w3, vault, strategy, 2010)
