# # From ipython console starting in mettalex-market-maker repo do:
# %load_ext autoreload
# %autoreload 2
# import os, sys
# os.chdir('on-chain/scripts')
# sys.path.append(os.getcwd())
# sys.path.append('brownie_mettalex/scripts')
from connect_deployed import main
from brownie import network, Contract
import pandas as pd


def connect(network_name='development', deployment='local_deployment_358'):
    network.connect(network_name)
    contracts, actors = main(f'{deployment}.json')
    return contracts, actors


def distribute_initial_funds(contracts, actors):
    admin = actors['admin']
    oracle = actors['oracle']
    vault = contracts['vault']
    # Initial setup
    vault.updateOracle(oracle, {'from': admin})
    strategy = contracts['pool_controller']
    strategy.setSwapFee(0.02 * 10 ** 18, {'from': admin})
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


def get_orderbook(contracts, tok, tok_amounts=None):
    if tok_amounts is None:
        tok_amounts = [0.1, 1, 10, 100]
    coin = contracts['coin']
    strategy = contracts['pool_controller']
    balancer = contracts['balancer_pool']
    coin_scale = 10**coin.decimals()
    token_scale = 10**tok.decimals()
    if coin.decimals() == 6 and tok.decimals() == 5:
        # Decimals for original USDT collateral plan don't work well with Balancer math
        spot_factor = 10_000
    else:
        spot_factor = 1
    # Ask for given number of tokens
    ask_tok_amount = tok_amounts[::-1]
    ask_coin_amount = [
        strategy.getExpectedInAmount(coin, tok, tok_amount*token_scale)[0] / coin_scale
        for tok_amount in ask_tok_amount
    ]
    ask_price = [c/t for c, t in zip(ask_coin_amount, ask_tok_amount)]
    ask_spot_with_fee = balancer.getSpotPrice(coin, tok) / 10**18 / token_scale * spot_factor
    spot_price = balancer.getSpotPriceSansFee(coin, tok) / 10**18 / token_scale * spot_factor
    bid_spot_with_fee = 1/(balancer.getSpotPrice(tok, coin) / 10**18) / token_scale * spot_factor
    bid_tok_amount = tok_amounts[::]
    bid_coin_amount = [
        strategy.getExpectedOutAmount(tok, coin, tok_amount * token_scale)[0] / coin_scale
        for tok_amount in bid_tok_amount
    ]
    bid_price = [c/t for c, t in zip(bid_coin_amount, bid_tok_amount)]
    desc = ['Ask']*len(ask_price) + ['Ask Spot with Fee', 'Spot sans Fee', 'Bid Spot with Fee'] + ['Bid']*len(bid_price)
    prices = ask_price + [ask_spot_with_fee, spot_price, bid_spot_with_fee] + bid_price
    tok_amounts = ask_tok_amount + [0, 0, 0] + bid_tok_amount
    coin_amounts = ask_coin_amount + [0, 0, 0] + bid_coin_amount
    df_o = pd.DataFrame({'desc': desc, 'token': tok_amounts, 'coin': coin_amounts, 'price': prices})
    return df_o


# def expected_price_from_coin(coin, token_out, amount_in):
#     coin_scale = 10**coin.decimals()
#
#     return int((d2w(amount_in) / strategy.getExpectedOutAmount(coin, token_out, d2w(amount_in))[0])*10**18)

if __name__ == '__main__':
    contracts, actors = connect()
    distribute_initial_funds(contracts, actors)
    supply_liquidity(contracts, actors)
