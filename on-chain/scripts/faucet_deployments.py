from mettalex_contract_setup import connect, create_contract, deploy_contract, set_token_whitelist, connect_contract
from pathlib import Path
import json
import os
import subprocess


def get_contracts(w3):
    usdt_faucet_build_file = Path(
        __file__).parent / ".." / 'mettalex-faucet' / 'build' / 'contracts' / 'USDTFaucet.json'
    eth_distributor_build_file = Path(
        __file__).parent / ".." / 'mettalex-faucet' / 'build' / 'contracts' / 'EthDistributor.json'

    coin_build_file = Path(__file__).parent / ".." / 'mettalex-vault' / \
        'build' / 'contracts' / 'CoinToken.json'

    contracts = {
        'USDTFaucet': create_contract(w3, usdt_faucet_build_file),
        'ETHDistributor': create_contract(w3, eth_distributor_build_file),
        'Coin': create_contract(w3, coin_build_file)
    }
    return contracts


def deploy(w3, contracts):
    account = w3.eth.defaultAccount

    if not os.path.isfile('args.json'):
        print('No args file')
        return

    with open('args.json', 'r') as f:
        args = json.load(f)

    usdt_faucet = deploy_contract(
        w3, contracts['USDTFaucet'], *args['USDTFaucet'])
    eth_distributor = deploy_contract(
        w3, contracts['ETHDistributor'], *args['ETHDistributor'])

    contract_addresses = {
        'USDTFaucet': usdt_faucet.address,
        'ETHDistributor': eth_distributor.address
    }
    return contract_addresses


def deployUSDTFaucet(w3, contracts):
    account = w3.eth.defaultAccount

    if not os.path.isfile('args.json'):
        print('No args file')
        return

    with open('args.json', 'r') as f:
        args = json.load(f)

    usdt_faucet = deploy_contract(
        w3, contracts['USDTFaucet'], *args['USDTFaucet'])

    print(f'USDT faucet deployed at address: {usdt_faucet.address}')

    return usdt_faucet.address


# setup
w3, admin = connect('bsc-mainnet', 'admin')
contracts = get_contracts(w3)
deployed_contract_address = deployUSDTFaucet(w3, contracts)

print(deployed_contract_address)

# coin address on bsc-mainnet
coin = connect_contract(
    w3, contracts['Coin'], '0x6e71C530bAdEB04b95C64a8ca61fe0b946A94525')

set_token_whitelist(w3, coin, deployed_contract_address["USDTFaucet"], True)
