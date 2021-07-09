# # From ipython console starting in mettalex-market-maker repo do:
# %load_ext autoreload
# %autoreload 2
# import os, sys
# os.chdir('on-chain/scripts')
# sys.path.append(os.getcwd())
# sys.path.append('brownie_mettalex/scripts')
from connect_deployed import main
from brownie import network, Contract


def connect(network_name='development', deployment='local_deployment_358'):
    network.connect(network_name)
    contracts, actors = main(f'{deployment}.json')
    return contracts, actors


def distribute_initial_funds(contracts, actors):
    admin = actors['admin']
    oracle = actors['oracle']
    vault = contracts['vault']
    vault.updateOracle(oracle, {'from': admin})
    lp = actors['lp']
    trader = actors['trader']
    coin = contracts['coin']
    coin_scale = 10**coin.decimals()
    coin.transfer(lp, 1_000_000 * coin_scale, {'from': admin})
    coin.transfer(trader, 100_000 * coin_scale, {'from': admin})


def supply_liquidity(contracts, actors):
    lp = actors['lp']
    trader = actors['trader']
    coin = contracts['coin']
    pool = contracts['y_vault']
    coin_scale = 10**coin.decimals()
    coin.approve(pool, 1_000_000 * coin_scale, {'from': lp})
    pool.deposit(1_000_000 * coin_scale, {'from': lp})
    pool.earn({'from': lp})


# def expected_price_from_coin(coin, token_out, amount_in):
#     coin_scale = 10**coin.decimals()
#
#     return int((d2w(amount_in) / strategy.getExpectedOutAmount(coin, token_out, d2w(amount_in))[0])*10**18)

if __name__ == '__main__':
    contracts, actors = connect()
    distribute_initial_funds(contracts, actors)
    supply_liquidity(contracts, actors)
