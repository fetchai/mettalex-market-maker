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
        make --directory=mettalex-balancer
        make --directory=mettalex-balancer
        make --directory=mettalex-vault
        make --directory=mettalex-vault
        make --directory=mettalex-vault
        make --directory=mettalex-vault
        make --directory=mettalex-yearn
        make --directory=mettalex-yearn
        make --directory=pool-controller
        make --directory=mettalex-reward
        :return:
    """
    bfactory_build_file = Path(
        __file__).parent / ".." / 'mettalex-balancer' / 'build' / 'contracts' / 'BFactory.json'
    bpool_build_file = Path(
        __file__).parent / ".." / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'

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

    build_file_name = f'StrategyBalancerMettalexV3.json'

    pool_controller_build_file = Path(
        __file__).parent / ".." / 'pool-controller' / 'build' / 'contracts' / 'StrategyBalancerMettalexV3.json'

    
    strategy_helper_build_file = Path(
        __file__).parent / ".." / 'pool-controller' / 'build' / 'contracts' / 'StrategyHelper.json'


    reward_build_file = Path(
        __file__).parent / ".." / 'mettalex-reward' / 'build' / 'contracts' / 'Reward.json'

    abi_bytecode = {
        'balancer_factory': extract(bfactory_build_file),
        'balancer_pool': extract(bpool_build_file),
        'coin': extract(coin_build_file),
        'position': extract(position_build_file),
        'vault': extract(mettalex_vault_build_file),
        'y_controller': extract(yvault_controller_build_file),
        'y_vault': extract(yvault_build_file),
        'pool_controller': extract(pool_controller_build_file),
        'strategy_helper': extract(strategy_helper_build_file),
        'reward': extract(reward_build_file)
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