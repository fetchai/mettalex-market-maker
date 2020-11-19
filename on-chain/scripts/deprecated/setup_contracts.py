import os
import subprocess
from pathlib import Path
import json
import argparse

os.environ['WEB3_PROVIDER_URI'] = 'http://127.0.0.1:8545'


def connect():
    from web3.auto import w3
    from web3.middleware import construct_sign_and_send_raw_middleware

    admin = w3.eth.account.from_key('')
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


def deploy_upgradeable_strategy(w3, y_controller, *args):
    contract_dir = Path(__file__).parent / 'pool-controller'
    current_dir = os.getcwd()
    os.chdir(contract_dir)
    acct = w3.eth.defaultAccount
    result = subprocess.run(
        ['npx', 'oz', 'deploy', '-n', 'development', '-k', 'upgradeable', '-f', acct,
         'StrategyBalancerMettalex', y_controller.address] + [arg.address for arg in args],
        capture_output=True
    )
    strategy_address = result.stdout.strip().decode('utf-8')
    os.chdir(current_dir)
    strategy = connect_strategy(w3, strategy_address)
    return strategy


def upgrade_strategy(w3, strategy, y_controller, *args):
    contract_dir = Path(__file__).parent / 'pool-controller'
    current_dir = os.getcwd()
    os.chdir(contract_dir)
    acct = w3.eth.defaultAccount
    result = subprocess.run(
        ['npx', 'oz', 'upgrade', '-n', 'development', '--init', 'initialize',
         'StrategyBalancerMettalex',
         '--args', y_controller.address] + [arg.address for arg in args],
        capture_output=True
    )
    os.chdir(current_dir)
    print(result.stderr.decode('utf-8'))
    strategy = connect_strategy(w3, strategy.address)
    return strategy


def deploy(w3, contracts, contract_cache_file='contract_cache.json'):
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
    strategy = deploy_upgradeable_strategy(
        w3,
        y_controller,
        coin,
        balancer,
        vault,
        ltk,
        stk
    )
    deployed_contracts = {
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
    with open(contract_cache_file, 'w') as f:
        json.dump(deployed_contracts, f)
    return balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy


def connect_deployed(contract_cache_file='contract_cache.json'):
    if not os.path.isfile(contract_cache_file):
        print('No cache file')
        return
    with open(contract_cache_file, 'r') as f:
        contract_cache = json.load(f)
    w3, admin = connect()
    contracts = get_contracts(w3)
    deployed_contracts = {
        k: connect_contract(w3, contracts[k], contract_cache[k]) for k in contracts.keys()
    }
    return w3, deployed_contracts


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


def set_autonomous_market_maker(w3, vault, strategy):
    acct = w3.eth.defaultAccount
    old_amm = vault.functions.automatedMarketMaker().call()
    tx_hash = vault.functions.updateAutomatedMarketMaker(strategy.address).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    new_amm = vault.functions.automatedMarketMaker().call()
    vault_name = vault.functions.contractName().call()
    print(f'{vault_name} strategy changed from {old_amm} to {new_amm}')


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
    tx_hash = balancer.functions.setController(controller_address).transact({'from': acct, 'gas': 1_000_000})
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    balancer_controller = balancer.functions.getController().call()
    print(f'Balancer controller {balancer_controller}')


def set_price(w3, vault, price):
    acct = w3.eth.defaultAccount
    old_spot = vault.functions.priceSpot().call()
    tx_hash = vault.functions.updateSpot(price).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    new_spot = vault.functions.priceSpot().call()
    vault_name = vault.functions.contractName().call()
    print(f'{vault_name} spot changed from {old_spot} to {new_spot}')


def set_yvault_controller(w3, y_controller, y_vault_address, token_address):
    acct = w3.eth.defaultAccount
    tx_hash = y_controller.functions.setVault(token_address, y_vault_address).transact({'from': acct, 'gas': 1_000_000})
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print('yVault added in yController')


def full_setup():
    w3, admin = connect()
    contracts = get_contracts(w3)
    balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy = deploy(w3, contracts)
    whitelist_vault(w3, vault, ltk, stk)
    set_strategy(w3, y_controller, coin, strategy)
    set_yvault_controller(w3, y_controller, y_vault.address, coin.address)
    set_balancer_controller(w3, balancer, strategy)
    set_autonomous_market_maker(w3, vault, strategy)  # Zero fees for AMM
    set_price(w3, vault, 2500000)
    return w3, admin, balancer_factory, balancer, coin, ltk, stk, vault, y_controller, y_vault, strategy


def get_spot_price(w3, balancer, tok_in, tok_out, unitless=False, include_fee=False):
    """Get spot price for tok_out in terms of number of tok_in required to purchase
    NB: copied from setup_testnet_pool

    :param w3: Web3 connection
    :param balancer: Web3 contract for pool
    :param tok_in: Web3 contract for input token e.g. ltok to sell Long position to pool
    :param tok_out: Web3 contract for output token e.g. ctok to receive Collateral token
    :param unitless: default True, if False amount is scaled by token decimals
    :param include_fee: default True, if False ignore swap fees
    :return: number of input tokens required for each output token
        e.g. if price is $50 per long token then
            spot price  ctok -> ltok = 50 ($50 required for 1 LTK)
                        ltok -> ctok = 0.02 (0.02 LTK (20kg) required for $1)
    """
    # Spot price is number of tok_in required for 1 tok_out (unitless)
    if include_fee:
        spot_price = balancer.functions.getSpotPrice(
            tok_in.address, tok_out.address
        ).call()
    else:
        spot_price = balancer.functions.getSpotPriceSansFee(
            tok_in.address, tok_out.address
        ).call()
    if not unitless:
        # Take decimals into account
        spot_price = spot_price * 10 ** (
                tok_out.functions.decimals().call()
                - tok_in.functions.decimals().call()
                - 18)
    return spot_price


def swap_amount_in(w3, balancer, tok_in, qty_in, tok_out, customAccount=None, min_qty_out=None, max_price=None):
    acct = w3.eth.defaultAccount
    if customAccount:
        acct = customAccount
    print(
        f'User: {acct} making a swap in balancer. Token_in: ${tok_in.functions.symbol().call()} Token_out: ${tok_out.functions.symbol().call()}')
    qty_in_unitless = int(qty_in * 10 ** (tok_in.functions.decimals().call()))

    if qty_in_unitless > tok_in.functions.allowance(acct, balancer.address).call():
        tx_hash = tok_in.functions.approve(balancer.address, qty_in_unitless).transact(
            {'from': acct, 'gas': 1_000_000}
        )
        tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

    if min_qty_out is None:
        # Default to allowing 10% slippage
        spot_price = get_spot_price(w3, balancer, tok_in, tok_out, unitless=False)
        print('spot price is', spot_price)
        min_qty_out = qty_in / spot_price * 0.9
        print(f'Minimum output token quantity not specified: using {min_qty_out}')

    if max_price is None:
        spot_price_unitless = get_spot_price(w3, balancer, tok_in, tok_out, unitless=True)
        max_price = int(spot_price_unitless * 1 / 0.09)
        print(f'Max price not specified: using {max_price}')

    min_qty_out_unitless = int(min_qty_out * 10 ** (tok_out.functions.decimals().call()))

    tx_hash = balancer.functions.swapExactAmountIn(
        tok_in.address, qty_in_unitless,
        tok_out.address, min_qty_out_unitless,
        max_price
    ).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    return tx_hash


def deposit(w3, y_vault, coin, amount, customAccount=None):
    acct = w3.eth.defaultAccount
    if customAccount:
        acct = customAccount
    amount_unitless = int(amount * 10 ** (coin.functions.decimals().call()))
    tx_hash = coin.functions.approve(y_vault.address, amount_unitless).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    tx_hash = y_vault.functions.deposit(amount_unitless).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(f'Deposit in YVault. Amount: {amount} coin. Depositer: {acct}')


def earn(w3, y_vault):
    acct = w3.eth.defaultAccount
    tx_hash = y_vault.functions.earn().transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(f'Liquidity supplied to AMM balancer. Earn Function Caller: {acct}')


def withdraw(w3, y_vault, amount, customAccount=None):
    acct = w3.eth.defaultAccount
    if customAccount:
        acct = customAccount
    amount_unitless = amount * 10 ** (y_vault.functions.decimals().call())
    tx_hash = y_vault.functions.withdraw(amount_unitless).transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(f'Withdraw from YVault. Amount: {amount} shares. Withdrawer: {acct}')


def distribute_coin(w3, coin, amount=200000, customAccount=None):
    acct = w3.eth.defaultAccount
    if customAccount:
        acct = customAccount
    transfer_amount = amount * 10 ** (coin.functions.decimals().call())
    tx_hash = coin.functions.transfer(acct, transfer_amount).transact(
        {'from': w3.eth.defaultAccount, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(f'Coin distribution successful. From = {w3.eth.defaultAccount} To = {acct} Amount = {amount}')


def mintPositionTokens(w3, vault, coin, collateralAmount=20000, customAccount=None):
    acct = w3.eth.defaultAccount
    if customAccount:
        acct = customAccount
    collateralAmount_unitless = collateralAmount * 10 ** (coin.functions.decimals().call())
    tx_hash = coin.functions.approve(vault.address, collateralAmount_unitless).transact(
        {'from': customAccount, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

    tx_hash = vault.functions.mintFromCollateralAmount(collateralAmount_unitless).transact(
        {'from': customAccount, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(f'Position tokens minted. Locked Coin: {collateralAmount} Minter: {acct}')


def simulate_scenario():
    (w3, admin, balancer_factory, balancer,
     coin, ltk, stk, vault,
     y_controller, y_vault, strategy) = full_setup()

    print('\nSystem Setup Completed\n')

    reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)

    # accounts[0] or default account hols all the tokens.
    user1 = w3.eth.accounts[1]
    user2 = w3.eth.accounts[2]
    user3 = w3.eth.accounts[3]
    user4 = w3.eth.accounts[4]

    distribute_coin(w3, coin, 200000, user1)
    distribute_coin(w3, coin, 200000, user2)
    distribute_coin(w3, coin, 200000, user3)
    distribute_coin(w3, coin, 200000, user4)

    mintPositionTokens(w3, vault, coin, 100000, user2)
    mintPositionTokens(w3, vault, coin, 100000, user3)
    mintPositionTokens(w3, vault, coin, 100000, user4)

    reporter.print_balances(w3.eth.defaultAccount, 'User 0')
    reporter.print_balances(user1, 'User 1')
    reporter.print_balances(user2, 'User 2')
    reporter.print_balances(user3, 'User 3')
    reporter.print_balances(user4, 'User 4')

    deposit(w3, y_vault, coin, 200000, user1)
    deposit(w3, y_vault, coin, 100000, user2)
    deposit(w3, y_vault, coin, 100000, user3)
    deposit(w3, y_vault, coin, 100000, user4)
    deposit(w3, y_vault, coin, 200000)
    earn(w3, y_vault)

    reporter.print_balances(y_vault.address, 'Y Vault')
    reporter.print_balances(balancer.address, 'Balancer AMM')
    reporter.print_balances(w3.eth.defaultAccount, 'User 0')
    reporter.print_balances(user1, 'User 1')
    reporter.print_balances(user2, 'User 2')
    reporter.print_balances(user3, 'User 3')
    reporter.print_balances(user4, 'User 4')

    swap_amount_in(w3, balancer, ltk, 500, stk, user2, 100);
    swap_amount_in(w3, balancer, stk, 500, ltk, user3, 100);
    swap_amount_in(w3, balancer, ltk, 500, stk, user4, 100);

    reporter.print_balances(y_vault.address, 'Y Vault')
    reporter.print_balances(balancer.address, 'Balancer AMM')
    reporter.print_balances(w3.eth.defaultAccount, 'User 0')
    reporter.print_balances(user1, 'User 1')
    reporter.print_balances(user2, 'User 2')
    reporter.print_balances(user3, 'User 3')
    reporter.print_balances(user4, 'User 4')

    withdraw(w3, y_vault, 200000)
    withdraw(w3, y_vault, 200000, user1)

    reporter.print_balances(y_vault.address, 'Y Vault')
    reporter.print_balances(balancer.address, 'Balancer AMM')
    reporter.print_balances(w3.eth.defaultAccount, 'User 0')
    reporter.print_balances(user1, 'User 1')


class BalanceReporter(object):
    def __init__(self, w3, coin, ltk, stk, y_vault):
        self.w3 = w3
        self.coin = coin
        self.ltk = ltk
        self.stk = stk
        self.y_vault = y_vault
        self.coin_scale = 10 ** 18
        self.ltk_scale = 10 ** 6
        self.stk_scale = 10 ** 6
        self.y_vault_scale = 10 ** 18

    def get_balances(self, address):
        coin_balance = self.coin.functions.balanceOf(address).call()
        ltk_balance = self.ltk.functions.balanceOf(address).call()
        stk_balance = self.stk.functions.balanceOf(address).call()
        y_vault_balance = self.y_vault.functions.balanceOf(address).call()
        return coin_balance, ltk_balance, stk_balance, y_vault_balance

    def print_balances(self, address, name):
        coin_balance, ltk_balance, stk_balance, y_vault_balance = self.get_balances(address)
        print(f'\n{name} ({address}) has {y_vault_balance / 10 ** 18:0.2f} vault shares')
        print(
            f'  {coin_balance / 10 ** 18:0.2f} coin, {ltk_balance / 10 ** 6:0.2f} LTK, {stk_balance / 10 ** 6:0.2f} STK\n')


class Balancer(object):
    def __init__(self, w3, balancer):
        self.w3 = w3
        self.balancer = balancer

    def get_spot_price(self, tok_in, tok_out, **kwargs):
        get_spot_price(self.w3, self.balancer, tok_in, tok_out, **kwargs)

    def swap_amount_in(self, tok_in, qty_in, tok_out, **kwargs):
        swap_amount_in(self.w3, self.balancer, tok_in, qty_in, tok_out, **kwargs)


class System(object):
    def __init__(self):
        self.w3 = None
        self.admin = None
        self.balancer_factory = None
        self.balancer = None
        self.coin = None
        self.ltk = None
        self.stk = None
        self.vault = None
        self.y_controller = None
        self.y_vault = None
        self.strategy = None

    def deploy(self):
        (
            self.w3, self.admin, self.balancer_factory, self.balancer,
            self.coin, self.ltk, self.stk, self.vault, self.y_controller,
            self.y_vault, self.strategy
        ) = full_setup()

    def get_balancer(self):
        return Balancer(self.w3, self.balancer)


if __name__ == '__main__':
    parser = argparse.ArgumentParser('Mettalex System Setup')
    parser.add_argument(
        '--action', '-a', dest='action', default='deploy',
        help='Action to perform: deposit, earn, connect_balancer, upgrade, simulation ( end to end simulation ), deploy (default)'
    )
    parser.add_argument(
        '--quantity', '-q', dest='qty', default=0,
        help='Quantity of collateral tokens to transfer (scaled)'
    )

    args = parser.parse_args()
    if args.action == 'simulation':
        simulate_scenario()
    if args.action == 'deploy':
        (w3, admin, balancer_factory, balancer,
         coin, ltk, stk, vault,
         y_controller, y_vault, strategy) = full_setup()
    # elif args.action == 'connect_balancer':
    #     w3, admin = connect()
    #     balancer = connect_balancer(w3)
    #     set_balancer_controller(w3, balancer, controller_address='0x9b1f7F645351AF3631a656421eD2e40f2802E6c0')

    else:
        w3, contracts = connect_deployed()
        (
            balancer_factory, balancer, coin, ltk, stk, vault,
            y_controller, y_vault, strategy
        ) = (
            contracts[name] for name in [
            'BFactory', 'BPool', 'Coin', 'Long', 'Short', 'Vault',
            'YController', 'YVault', 'PoolController'
        ]
        )
        reporter = BalanceReporter(w3, coin, ltk, stk, y_vault)
        if args.action == 'deposit':
            deposit(w3, y_vault, coin, float(args.qty))
            reporter.print_balances(w3.eth.defaultAccount, 'User')
            reporter.print_balances(y_vault.address, 'Vault')
            reporter.print_balances(balancer.address, 'AMM')

        elif args.action == 'earn':
            earn(w3, y_vault)
            reporter.print_balances(w3.eth.defaultAccount, 'User')
            reporter.print_balances(y_vault.address, 'Vault')
            reporter.print_balances(balancer.address, 'AMM')

        elif args.action == 'upgrade':
            strategy = upgrade_strategy(
                w3,
                strategy,
                y_controller,
                coin,
                balancer,
                vault,
                ltk,
                stk
            )
