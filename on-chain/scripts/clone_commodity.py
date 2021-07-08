from mettalex_contract_setup import connect
import json
import os
from pathlib import Path
from subprocess import run
import argparse


def get_commodity(w3, pool_address=None, deployed_hash=None):
    if deployed_hash is None:
        deployed_hash = '729c4df56d28af211ed4c6f55c1d47c04a80ee96'
    file_path = Path(__file__).parent
    with open(os.path.join(file_path, 'deployed', f'{deployed_hash}.json'), 'r') as f:
        deployed = json.load(f)

    pool = w3.eth.contract(abi=deployed['y_vault']['abi'], address=pool_address)
    coin = w3.eth.contract(
        abi=deployed['coin']['abi'],
        address=pool.functions.token().call()
    )
    y_controller = w3.eth.contract(
        abi=deployed['y_controller']['abi'],
        address=pool.functions.controller().call()
    )
    strategy = w3.eth.contract(
        abi=deployed['pool_controller']['abi'],
        address=y_controller.functions.strategies(coin.address).call()
    )
    ltk = w3.eth.contract(
        abi=deployed['position']['abi'],
        address=strategy.functions.longToken().call()
    )
    stk = w3.eth.contract(
        abi=deployed['position']['abi'],
        address=strategy.functions.shortToken().call()
    )
    vault = w3.eth.contract(
        abi=deployed['vault']['abi'],
        address=strategy.functions.mettalexVault().call()
    )
    balancer = w3.eth.contract(
        abi=deployed['balancer_pool']['abi'],
        address=strategy.functions.balancer().call()
    )

    commodity = {
        'y_vault': pool,
        'y_controller': y_controller,
        'coin': coin,
        'strategy': strategy,
        'long': ltk,
        'short': stk,
        'vault': vault,
        'balancer': balancer
    }

    return commodity


def create_ctor_args(commodity, out_file=None):
    coin = commodity['coin']
    coin_args = [coin.functions[f]().call() for f in ['name', 'symbol', 'decimals']]

    decimals_precision = 1
    ltk = commodity['long']
    ltk_args = [ltk.functions[f]().call() for f in ['name', 'symbol', 'decimals']] + [decimals_precision]

    stk = commodity['short']
    stk_args = [stk.functions[f]().call() for f in ['name', 'symbol', 'decimals']] + [decimals_precision]

    vault = commodity['vault']
    price_cap = vault.functions.priceCap().call()
    price_floor = vault.functions.priceFloor().call()
    multiplier = int(vault.functions.collateralPerUnit().call() / (price_cap - price_floor))
    fee_rate = int(
        vault.functions.collateralFeePerUnit().call() / ((price_cap + price_floor)*multiplier/200000)
     )

    vault_args = [
        int(price_cap / 10**decimals_precision),  # Cap
        int(price_floor / 10 ** decimals_precision),  # Floor
        multiplier,
        fee_rate,
        vault.functions.contractName().call(),  # Name
        '',   # Oracle
    ]

    ctor_args = {
        "Coin": coin_args,   # e.g. ["Tether USD", "wUSDT", 6],
        # Not used generallyL "USDT": [100000000000, "USDT", "USDT", 5],
        "Long": ltk_args,  # e.g. ["Long Position", "LTOK", 5, 1],
        "Short": stk_args,  # e.g. ["Short Position", "STOK", 5, 1],
        "Vault": vault_args,  # [300, 200, 1, 300, "Mettalex Vault", ""],
        # "USDTFaucet": ["0x6e71C530bAdEB04b95C64a8ca61fe0b946A94525", 10000000000],
        # "ETHDistributor": [
        #     "0x2407A3227aA2111Dd3563b7D24c231263da304d8",
        #     100000000000000000
        # ],
        "PoolController": []
    }
    write_output(ctor_args, out_file)

    return ctor_args


def create_deployment_json(commodity, out_file=None):
    deployment = {
        k: {'address': v.address, 'abi': v.abi}
        for k, v in commodity.items()
    }

    write_output(deployment, out_file)

    return deployment


def write_output(body, out_file=None):
    if out_file is not None:
        with open(out_file, 'w') as f:
            json.dump(body, f)
