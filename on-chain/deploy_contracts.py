import os
import subprocess
from pathlib import Path
import json
import argparse


def read_config():
    # Read configuration from local file system
    # For cloud function replace with reading from secrets manager
    with open(os.path.expanduser('~/.mettalex/config-dev.json'), 'r') as f:
        config = json.load(f)
    return config


def connect(network, account='user'):
    if network == 'local':
        from web3 import Web3

        w3 = Web3(Web3.HTTPProvider("http://127.0.0.1:8545"))
        try:
            w3.eth.defaultAccount = w3.eth.accounts[0]
            admin = w3.eth.accounts[0]
        except:
            raise Exception("Ensure ganache-cli is connected")
    elif network == 'kovan':
        config = read_config()
        os.environ['WEB3_INFURA_PROJECT_ID'] = config['infura']['project_id']
        os.environ['WEB3_INFURA_API_SECRET'] = config['infura']['secret']

        from web3.middleware import construct_sign_and_send_raw_middleware
        from web3.auto.infura.kovan import w3

        admin = w3.eth.account.from_key(config[account]['key'])
        w3.eth.defaultAccount = admin.address
        w3.middleware_onion.add(construct_sign_and_send_raw_middleware(admin))

    assert w3.isConnected()
    return w3, admin


def get_contracts(w3):
    """
        make --directory=mettalex-balancer deploy_pool_factory
        make --directory=mettalex-balancer deploy_balancer_amm
    #	make --directory=mettalex-coin deploy  # NB: Pool controller fails if actual USDT contract is used
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
        __file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BFactory.json'
    bpool_build_file = Path(
        __file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'

    # Use Mettalex vault version of CoinToken rather than USDT in mettalex-coin to avoid Solidity version issue
    coin_build_file = Path(__file__).parent / 'mettalex-vault' / \
        'build' / 'contracts' / 'CoinToken.json'
    # Use position token for both long and short tokens
    position_build_file = Path(
        __file__).parent / 'mettalex-vault' / 'build' / 'contracts' / 'PositionToken.json'
    mettalex_vault_build_file = Path(
        __file__).parent / 'mettalex-vault' / 'build' / 'contracts' / 'Vault.json'

    yvault_controller_build_file = Path(
        __file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'Controller.json'
    yvault_build_file = Path(
        __file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'yVault.json'

    # May need to deploy pool controller via openzeppelin cli for upgradeable contract
    pool_controller_build_file = Path(
        __file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'yVault.json'

    contracts = {
        'BFactory': create_contract(w3, bfactory_build_file),
        'BPool': create_contract(w3, bpool_build_file),
        'Coin': create_contract(w3, coin_build_file),
        'Long': create_contract(w3, position_build_file),
        'Short': create_contract(w3, position_build_file),
        'Vault': create_contract(w3, mettalex_vault_build_file),
        'YController': create_contract(w3, yvault_controller_build_file),
        'YVault': create_contract(w3, yvault_build_file),
        'PoolController': create_contract(w3, pool_controller_build_file),
    }
    return contracts


def create_contract(w3, build_file):
    with open(build_file, 'r') as f:
        contract_details = json.load(f)
    abi = contract_details['abi']
    bytecode = contract_details['bytecode']
    contract = w3.eth.contract(abi=abi, bytecode=bytecode)
    return contract


def deploy_contract(w3, contract, *args):
    tx_hash = contract.constructor(*args).transact()
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    deployed_contract = w3.eth.contract(
        address=tx_receipt.contractAddress,
        abi=contract.abi
    )
    return deployed_contract


def connect_contract(w3, contract, address):
    """Connect to existing deployed contract

    :param w3:
    :param contract:
    :param address:
    :return:
    """
    deployed_contract = w3.eth.contract(
        address=address,
        abi=contract.abi
    )
    return deployed_contract


def connect_deployed(w3, contracts):
    if not os.path.isfile('contract_address.json'):
        print('No address file')
        return
    if not os.path.isfile('args.json'):
        print('No args file')
        return

    with open('args.json', 'r') as f:
        args = json.load(f)
    with open('contract_address.json', 'r') as f:
        contract_cache = json.load(f)

    id = w3.eth.chainId
    network = 'local'
    if id == 42:
        network = 'kovan'

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
                deployed_contracts[k] = deploy_upgradeable_strategy(
                    w3, deployed_contracts['YController'], deployed_contracts['Coin'], deployed_contracts['BPool'], deployed_contracts['Vault'], deployed_contracts['Long'], deployed_contracts['Short'])
            else:
                deployed_contracts[k] = deploy_contract(
                    w3, contracts[k], *args[network][k])
        if  k == 'PoolController':                  
            print(deployed_contracts['PoolController'].address)
        contract_cache[k] = deployed_contracts[k].address

    with open('contract_cache.json', 'w') as f:
        json.dump(contract_cache, f)
    return deployed_contracts


def deploy(w3, contracts):
    acct = w3.eth.defaultAccount
    balancer_factory = deploy_contract(w3, contracts['BFactory'])
    balancer = create_balancer_pool(w3, contracts['BPool'], balancer_factory)
    coin = deploy_contract(w3, contracts['Coin'], 'Tether USD', 'USDT', 18)
    tok_version = 1
    ltk = deploy_contract(
        w3, contracts['Long'], 'Long Position', 'LTOK', 6, tok_version)
    stk = deploy_contract(
        w3, contracts['Short'], 'Short Position', 'STOK', 6, tok_version)
    vault = deploy_contract(
        w3, contracts['Vault'],
        'Mettalex Vault', tok_version, coin.address, ltk.address, stk.address,
        acct, balancer.address, 3000000, 2000000, 100000000, 300
    )
    y_controller = deploy_contract(w3, contracts['YController'], acct)
    y_vault = deploy_contract(
        w3, contracts['YVault'], coin.address, y_controller.address)

    # Use OpenZeppelin CLI to deploy upgradeable contract for ease of development
    strategy = deploy_upgradeable_strategy(
        w3,
        y_controller,
        coin,
        balancer,
        vault,
        ltk,
        stk
    )
    contract_addresses = {
        'BFactory': balancer_factory.address,
        'BPool': balancer.address,
        'Coin': coin.address,
        'Long': ltk.address,
        'Short': stk.address,
        'Vault': vault.address,
        'YVault': y_vault.address,
        'YController': y_controller.address,
        'PoolController': strategy.address
    }
    with open('contract_cache.json', 'w') as f:
        json.dump(contract_addresses, f)

    deployed_contracts = {
        'BFactory': balancer_factory,
        'BPool': balancer,
        'Coin': coin,
        'Long': ltk,
        'Short': stk,
        'Vault': vault,
        'YVault': y_vault,
        'YController': y_controller,
        'PoolController': strategy
    }
    return deployed_contracts


def create_balancer_pool(w3, pool_contract, balancer_factory):
    acct = w3.eth.defaultAccount
    tx_hash = balancer_factory.functions.newBPool().transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    # Find pool address from contract event
    receipt = balancer_factory.events.LOG_NEW_POOL().processReceipt(tx_receipt)
    pool_address = receipt[0]['args']['pool']
    balancer = w3.eth.contract(
        address=pool_address,
        abi=pool_contract.abi
    )
    return balancer


def deploy_upgradeable_strategy(w3, y_controller, *args):
    contract_dir = Path(__file__).parent / 'pool-controller'
    current_dir = os.getcwd()
    os.chdir(contract_dir)
    acct = w3.eth.defaultAccount

    id = w3.eth.chainId
    network = 'development'
    if id == 42:
        network = 'kovan'
    result = subprocess.run(
        ['npx', 'oz', 'deploy', '-n', network, '-k', 'upgradeable', '-f', acct,
         'StrategyBalancerMettalex', y_controller.address] + [arg.address for arg in args],
        capture_output=True
    )
    strategy_address = result.stdout.strip().decode('utf-8')
    os.chdir(current_dir)
    strategy = connect_strategy(w3, strategy_address)
    return strategy


def connect_strategy(w3, address='0x9b1f7F645351AF3631a656421eD2e40f2802E6c0'):
    build_file = Path(__file__).parent / 'pool-controller' / \
        'build' / 'contracts' / 'StrategyBalancerMettalex.json'
    with open(build_file, 'r') as f:
        contract_details = json.load(f)

    # get abi
    abi = contract_details['abi']
    strategy = w3.eth.contract(abi=abi, address=address)
    return strategy


if __name__ == '__main__':
    parser = argparse.ArgumentParser('Mettalex System Setup')
    parser.add_argument(
        '--action', '-a', dest='action', default='deploy',
        help='Action to perform: connect, deploy (default)'
    )
    parser.add_argument(
        '--network', '-n', dest='network', default='local',
        help='For connecting to local or kovan network'
    )

    args = parser.parse_args()
    assert args.network == 'local' or args.network == 'kovan'

    w3, admin = connect(args.network)
    contracts = get_contracts(w3)

    if args.action == 'deploy':
        deployed_contracts = deploy(w3, contracts)
    elif args.action == 'connect':
        deployed_contracts = connect_deployed(w3, contracts)
