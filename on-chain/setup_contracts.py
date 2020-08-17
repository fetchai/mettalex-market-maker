import os
from pathlib import Path
import json

os.environ['WEB3_PROVIDER_URI'] = 'http://127.0.0.1:8545'


def connect():
    from web3.auto import w3
    from web3.middleware import construct_sign_and_send_raw_middleware

    admin = w3.eth.account.from_key('0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d')
    w3.middleware_onion.add(construct_sign_and_send_raw_middleware(admin))
    w3.eth.defaultAccount = admin.address
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
    bfactory_build_file = Path(__file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BFactory.json'
    bpool_build_file = Path(__file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'
    # Use Mettalex vault version of CoinToken rather than USDT in mettalex-coin to avoid Solidity version issue
    coin_build_file = Path(__file__).parent / 'mettalex-vault' / 'build' / 'contracts' / 'CoinToken.json'
    # Use position token for both long and short tokens
    position_build_file = Path(__file__).parent / 'mettalex-vault' / 'build' / 'contracts' / 'PositionToken.json'
    mettalex_vault_build_file = Path(__file__).parent / 'mettalex-vault' / 'build' / 'contracts' / 'Vault.json'
    yvault_controller_build_file = Path(__file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'Controller.json'
    yvault_build_file = Path(__file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'yVault.json'
    # May need to deploy pool controller via openzeppelin cli for upgradeable contract
    pool_controller_build_file = Path(__file__).parent / 'mettalex-yearn' / 'build' / 'contracts' / 'yVault.json'
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


def create_balancer_pool(w3, pool_contract, balancer_factory):
    acct = w3.eth.defaultAccount
    tx_hash = balancer_factory.functions.newBPool().transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    # Find pool address from contract event
    pool_address = balancer_factory.events.LOG_NEW_POOL().processReceipt(tx_receipt)[0]['args']['pool']
    balancer = w3.eth.contract(
        address=pool_address,
        abi=pool_contract.abi
    )
    return balancer


def deploy(w3, contracts):
    acct = w3.eth.defaultAccount
    balancer_factory = deploy_contract(w3, contracts['BFactory'])
    balancer = create_balancer_pool(w3, contracts['BPool'], balancer_factory)
    coin = deploy_contract(w3, contracts['Coin'], 'Tether USD', 'USDT', 18)
    tok_version = 1
    ltk = deploy_contract(w3, contracts['Long'], 'Long Position', 'LTOK', 6, tok_version)
    stk = deploy_contract(w3, contracts['Short'], 'Short Position', 'STOK', 6, tok_version)
    vault = deploy_contract(
        w3, contracts['Vault'],
        'Mettalex Vault', tok_version, coin.address, ltk.address, stk.address,
        acct, balancer.address, 3000000, 2000000, 100000000, 300
    )
    y_controller = deploy_contract(w3, contracts['YController'], acct)
    y_vault = deploy_contract(w3, contracts['YVault'], coin.address, y_controller.address)

    return balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault


def connect_balancer(w3):
    build_file = Path(__file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'
    with open(build_file, 'r') as f:
        contract_details = json.load(f)

    # get abi
    abi = contract_details['abi']
    balancer = w3.eth.contract(abi=abi, address='0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78')
    return balancer


if __name__ == '__main__':
    w3, admin = connect()
    balancer = connect_balancer(w3)
    controller_address = '0x9b1f7F645351AF3631a656421eD2e40f2802E6c0'
    tx_hash = balancer.functions.setController(controller_address).transact({'from': admin.address, 'gas': 1_000_000})
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    balancer_controller = balancer.functions.getController().call()
    print(f'Balancer controller {balancer_controller}')
