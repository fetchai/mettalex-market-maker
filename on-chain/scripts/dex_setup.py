import os
import subprocess
from pathlib import Path
import json
import argparse

from mettalex_contract_setup import connect, connect_contract, create_balancer_pool, full_setup, deploy_contract, get_contracts


def get_addresses(contract_file_name='contract_address.json'):
    contract_file = Path(__file__).parent / 'contract-cache' / contract_file_name
    if not os.path.isfile(contract_file):
        print('No address file')
        return
    if not os.path.isfile('args.json'):
        print('No args file')
        return

    with open('args.json', 'r') as f:
        args = json.load(f)
    with open(contract_file, 'r') as f:
        contract_cache = json.load(f)
    return contract_cache


def connect_deployed(w3, contracts, contract_cache):
    deployed_contracts = {}
    for k in contracts.keys():
        if contract_cache[k]:
            deployed_contracts[k] = connect_contract(
                w3, contracts[k], contract_cache[k])

        else:
            if k == 'BPool':
                deployed_contracts[k] = create_balancer_pool(
                    w3, contracts[k], connect_contract(w3, contracts['BFactory'], contract_cache['BFactory']))

            elif k == 'YController':
                deployed_contracts[k] = deploy_contract(
                    w3, contracts[k], w3.eth.defaultAccount)

            elif k == 'YVault':
                deployed_contracts[k] = deploy_contract(
                    w3, contracts[k], contract_cache['Coin'], contract_cache['YController'])

            elif k == 'PoolController':
                deployed_contracts[k] = deploy_contract(
                    w3, contracts[k], contract_cache['YController'], contract_cache['Coin'], contract_cache['BPool'], contract_cache['Vault'], contract_cache['Long'], contract_cache['Short'])

        contract_cache[k] = deployed_contracts[k].address

    return deployed_contracts, contract_cache


def store_cache(contract_cache, index, cache_file_name='contract_cache.json'):
    cache_file = Path(__file__).parent / 'contract-cache' / cache_file_name
    with open(cache_file, 'r') as f:
        addresses = json.load(f)

    if 'Commodities' not in addresses:
        addresses = {'Commodities': []}

    commodities = addresses['Commodities']
    commodities.append(contract_cache)

    with open(cache_file, 'w') as f:
        json.dump(addresses, f)


def setup_dex(w3, admin, contracts, deployed_contracts=None, contract_file='contract_address_dex.json'):
    contract_cache = get_addresses(contract_file)
    index = 0
    for commodity_address in contract_cache["Commodities"]:
        deployed_contracts, contract_cache = connect_deployed(
            w3, contracts, commodity_address)

        full_setup(w3, admin, deployed_contracts)
        store_cache(contract_cache, index)
        index += 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser('Mettalex System Setup')
    parser.add_argument(
        '--action', '-a', dest='action', default='deploy',
        help='Action to perform: connect, deploy (default), setup'
    )
    parser.add_argument(
        '--network', '-n', dest='network', default='local',
        help='For connecting to local, kovan, polygon-testnet, harmony-testnet, okexchain-testnet, avalanche-testnet or bsc-testnet network'
    )

    args = parser.parse_args()
    assert args.network in {'local', 'kovan', 'bsc-testnet', 'polygon', 'polygon-testnet', 'harmony-testnet', 'okexchain-testnet', 'avalanche-testnet'}

    w3, admin = connect(args.network, 'admin')
    contracts = get_contracts(w3)

    setup_dex(w3, admin, contracts)
