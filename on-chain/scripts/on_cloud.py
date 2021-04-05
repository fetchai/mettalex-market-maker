#!/usr/bin/env python3

from pathlib import Path
import json
import hashlib

def extract(build_file):
    with open(build_file, 'r') as f:
        contract_details = json.load(f)
    abi = contract_details['abi']
    bytecode = contract_details['bytecode']
    return ({
        "abi": abi,
        "bytecode": bytecode
    })

def main():
    """
        make --directory=mettalex-balancer deploy_pool_factory
        make --directory=mettalex-balancer deploy_balancer_amm
        make --directory=mettalex-vault deploy_coin
        make --directory=mettalex-vault deploy_long
        make --directory=mettalex-vault deploy_short
        make --directory=mettalex-vault deploy_vault
        make --directory=mettalex-yearn deploy_controller
        make --directory=mettalex-yearn deploy_vault
        make --directory=pool-controller deploy
        :return:
    """
    bfactory_build_file = Path(
        __file__).parent / ".." / 'mettalex-balancer' / 'build' / 'contracts' / 'BFactory.json'
    bpool_build_file = Path(
        __file__).parent / ".." / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'

    # Use Mettalex vault version of CoinToken rather than USDT in mettalex-coin to avoid Solidity version issue
    coin_build_file = Path(__file__).parent / ".." / 'mettalex-vault' / \
        'build' / 'contracts' / 'CoinToken.json'
    # Use position token for both long and short tokens
    position_build_file = Path(
        __file__).parent / ".." / 'mettalex-vault' / 'build' / 'contracts' / 'PositionToken.json'
    mettalex_vault_build_file = Path(
        __file__).parent / ".." / 'mettalex-vault' / 'build' / 'contracts' / 'Vault.json'

    yvault_controller_build_file = Path(
        __file__).parent / ".." / 'mettalex-yearn' / 'build' / 'contracts' / 'Controller.json'
    yvault_build_file = Path(
        __file__).parent / ".." / 'mettalex-yearn' / 'build' / 'contracts' / 'yVault.json'

    # Strategy contracts
    build_file_name = f'StrategyBalancerMettalexV3.json'

    pool_controller_build_file = Path(
        __file__).parent / ".." / 'pool-controller' / 'build' / 'contracts' / 'StrategyBalancerMettalexV3.json'

    abi_bytecode = {
        'balancer_factory': extract(bfactory_build_file),
        'balancer_pool': extract(bpool_build_file),
        'coin': extract(coin_build_file),
        'position': extract(position_build_file),
        'vault': extract(mettalex_vault_build_file),
        'y_controller': extract(yvault_controller_build_file),
        'y_vault': extract(yvault_build_file),
        'pool_controller': extract(pool_controller_build_file),
    }

    abi_bytecode_str = json.dumps(abi_bytecode, sort_keys=True)
    encoded_abi_bytecode = abi_bytecode_str.encode()
    filename = hashlib.sha1(encoded_abi_bytecode).hexdigest()
    print(filename)

    f = open(f'./cloud/{filename}.json', "x")
    f.write(abi_bytecode_str)
    f.close()

    return filename

if __name__ == "__main__":
    main()
# f = open(f'./cloud/{filename}.json')
# from_file = f.read()
# a = json.loads(from_file)
# print(a["coin"]["bytecode"])
# f.close()