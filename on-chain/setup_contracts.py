import os
import subprocess
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


def deploy_upgradeable_strategy(w3, y_controller):
    contract_dir = Path(__file__).parent / 'pool-controller'
    current_dir = os.getcwd()
    os.chdir(contract_dir)
    acct = w3.eth.defaultAccount
    result = subprocess.run(
        ['npx', 'oz', 'deploy', '-n', 'development', '-k', 'upgradeable', '-f', acct,
         'StrategyBalancerMettalex',  y_controller.address],
        capture_output=True
    )
    strategy_address = result.stdout.strip().decode('utf-8')
    os.chdir(current_dir)
    strategy = connect_strategy(w3, strategy_address)
    return strategy


def upgrade_strategy(w3, strategy, y_controller):
    contract_dir = Path(__file__).parent / 'pool-controller'
    current_dir = os.getcwd()
    os.chdir(contract_dir)
    acct = w3.eth.defaultAccount
    result = subprocess.run(
        ['npx', 'oz', 'upgrade', '-n', 'development', '--init', 'initialize',
         '--args', y_controller.address, 'StrategyBalancerMettalex'],
        capture_output=True
    )
    os.chdir(current_dir)
    print(result.stderr.decode('utf-8'))
    strategy = connect_strategy(w3, strategy.address)
    return strategy


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
    # Use OpenZeppelin CLI to deploy upgradeable contract for ease of development
    strategy = deploy_upgradeable_strategy(w3, y_controller)

    return balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy


def set_token_whitelist(w3, tok, address, state=True):
    acct = w3.eth.defaultAccount
    old_state = tok.functions.whitelist(address).call()
    tx_hash = tok.functions.setWhitelist(address, state).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    new_state = tok.functions.whitelist(address).call()
    tok_name = tok.functions.name().call()
    print(f'{tok_name} whitelist state for {address} changed from {old_state} to {new_state}')


def whitelist_vault(w3, vault, ltk, stk):
    set_token_whitelist(w3, ltk, vault.address, True)
    set_token_whitelist(w3, stk, vault.address, True)


def set_strategy(w3, y_controller, tok, strategy):
    acct = w3.eth.defaultAccount
    old_strategy = y_controller.functions.strategies(tok.address).call()
    tx_hash = y_controller.functions.setStrategy(tok.address, strategy.address).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    new_strategy = y_controller.functions.strategies(tok.address).call()
    tok_name = tok.functions.name().call()
    print(f'{tok_name} strategy changed from {old_strategy} to {new_strategy}')


def connect_balancer(w3):
    build_file = Path(__file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'
    with open(build_file, 'r') as f:
        contract_details = json.load(f)

    # get abi
    abi = contract_details['abi']
    balancer = w3.eth.contract(abi=abi, address='0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78')
    return balancer


def connect_strategy(w3, address='0x9b1f7F645351AF3631a656421eD2e40f2802E6c0'):
    build_file = Path(__file__).parent / 'pool-controller' / 'build' / 'contracts' / 'StrategyBalancerMettalex.json'
    with open(build_file, 'r') as f:
        contract_details = json.load(f)

    # get abi
    abi = contract_details['abi']
    strategy = w3.eth.contract(abi=abi, address=address)
    return strategy


def set_balancer_controller(w3, balancer, strategy, controller_address=None):
    acct = w3.eth.defaultAccount
    if controller_address is None:
        controller_address = strategy.address
    tx_hash = balancer.functions.setController(controller_address).transact({'from':acct, 'gas': 1_000_000})
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    balancer_controller = balancer.functions.getController().call()
    print(f'Balancer controller {balancer_controller}')


def full_setup():
    w3, admin = connect()
    contracts = get_contracts(w3)
    balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy = deploy(w3, contracts)
    whitelist_vault(w3, vault, ltk, stk)
    set_strategy(w3, y_controller, coin, strategy)
    set_balancer_controller(w3, balancer, strategy)
    return w3, admin, balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy


def deposit(w3, y_vault, coin, amount):
    acct = w3.eth.defaultAccount
    amount_unitless = int(amount * 10**(coin.functions.decimals().call()))
    tx_hash = coin.functions.approve(y_vault.address, amount_unitless).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    tx_hash = y_vault.functions.deposit(amount_unitless).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)


def earn(w3, y_vault):
    acct = w3.eth.defaultAccount
    tx_hash = y_vault.functions.earn().transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)


class BalanceReporter(object):
    def __init__(self, w3, coin, ltk, stk):
        self.w3 = w3
        self.coin = coin
        self.ltk = ltk
        self.stk = stk
        self.coin_scale = 10**18
        self.ltk_scale = 10**6
        self.stk_scale = 10**6

    def get_balances(self, address):
        coin_balance = self.coin.functions.balanceOf(address).call()
        ltk_balance = self.ltk.functions.balanceOf(address).call()
        stk_balance = self.stk.functions.balanceOf(address).call()
        return coin_balance, ltk_balance, stk_balance

    def print_balances(self, address, name):
        coin_balance, ltk_balance, stk_balance = self.get_balances(address)
        print(f'{name} ({address}) has {coin_balance/10**18:0.2f} coin, {ltk_balance/10**6:0.2f} LTK, {stk_balance/10**6:0.2f} STK')


if __name__ == '__main__':
    w3, admin = connect()
    balancer = connect_balancer(w3)
    set_balancer_controller(w3, balancer, controller_address='0x9b1f7F645351AF3631a656421eD2e40f2802E6c0')
