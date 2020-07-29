import os
import json
import base64
from web3.middleware import construct_sign_and_send_raw_middleware
from pathlib import Path
from glob import glob
import argparse


def read_config(contracts=None, deploy_date=None, get_related=True):
    # Read configuration from local file system
    # For cloud function replace with reading from secrets manager
    if contracts is None:
        contracts = [
            'COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT', 'BFACTORY', 'SS_BPOOL'
        ]

    with open(os.path.expanduser('~/.mettalex/config-dev.json'), 'r') as f:
        config = json.load(f)
    cache_dir = Path(__file__).parent.parent / 'cache'

    deployments_file = os.path.join(cache_dir, 'deployment_env.json')
    with open(deployments_file, 'r') as f:
        deployments = json.load(f)
    antier_deployments = deployments['antier_stg']['kovan']
    antier_deployments['COLLATERAL_TOKEN'] = antier_deployments['USDT']

    vaults = []
    if get_related:
        for k, v in antier_deployments['vault_contracts'].items():
            antier_deployments[k] = v
            contracts.append(k)
            vaults.append(k)

    contract_details = {}
    exchange = 'Antier'
    for contract in contracts:
        if contract in {'BFACTORY', 'SS_BPOOL'}:
            contract_file = sorted(glob(os.path.join(cache_dir, exchange, contract + '_*.json')))[-1]
        elif contract in vaults:
            contract_file = os.path.join(cache_dir, exchange, 'Vault', antier_deployments[contract][0])
        else:
            contract_file = os.path.join(cache_dir, exchange, antier_deployments[contract][0])
        with open(contract_file, 'r') as f:
            contract_details[contract] = json.load(f)

    return config, contract_details


def connect(contract_names=None, deploy_date=None, get_related=True):
    config, contract_details = read_config(
        contracts=contract_names, deploy_date=deploy_date, get_related=get_related
    )
    os.environ['WEB3_INFURA_PROJECT_ID'] = config['infura']['project_id']
    os.environ['WEB3_INFURA_API_SECRET'] = config['infura']['secret']

    if config['infura']['network'] == 'kovan':
        from web3.auto.infura.kovan import w3
    else:
        from web3.auto.infura import w3

    assert w3.isConnected()

    market_maker = w3.eth.account.from_key(config['maker']['key'])

    w3.middleware_onion.add(construct_sign_and_send_raw_middleware(market_maker))
    w3.eth.defaultAccount = market_maker.address

    contracts = {
        name: w3.eth.contract(
            address=contract_details[name]['address'],
            abi=contract_details[name]['abi']
        ) for name in contract_details
    }
    return w3, contracts


def print_balance(dest_address, contract_details=None):
    if contract_details is None:
        contract_names = ['COLLATERAL_TOKEN', 'CULONG', 'CUSHORT', 'SSLONG', 'SSSHORT', 'SRRLONG', 'SRRSHORT',
                          'SRSCSPRL', 'SRSCSPRS', 'BFACTORY', 'SS_BPOOL']
        w3, contract_details = connect(contract_names)

    def print_balance(name, address):
        tok = contract_details[name]
        tok_address = tok.address
        tok_decimals = tok.functions.decimals().call()
        tok_balance = tok.functions.balanceOf(address).call()/ 10 ** tok_decimals
        tok_symbol = tok.functions.symbol().call()
        print(f'{name:20} ({tok_address}): {tok_balance:8} {tok_symbol}')

    print(f'Wallet address {dest_address}')

    for contract in contract_details:
        print_balance(contract, dest_address)


def deploy_pool():
    w3, contracts = connect()
    factory = contracts['BFACTORY']
    acct = w3.eth.defaultAccount
    tx_hash = factory.functions.newBPool().transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    # Find pool address from contract event
    pool_address = factory.events.LOG_NEW_POOL().processReceipt(tx_receipt)[0]['args']['pool']
    print(f'New pool created at {pool_address}')


def approve_pool(w3, pool, tok, balance):
    acct = w3.eth.defaultAccount
    # Approve pool contract for token transfer
    tx_hash = tok.functions.approve(pool.address, balance).transact(
        {'from': acct, 'gas': 100_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    owner, spender, value = tok.events.Approval().processReceipt(tx_receipt)[0]['args'].values()
    value_scaled = value / (10 ** int(tok.functions.decimals().call()))
    tok_symbol = tok.functions.symbol().call()
    print(f'{owner} approved {spender} to spend {value_scaled} {tok_symbol}')


def bind_token(w3, pool, tok, balance, dnorm):
    acct = w3.eth.defaultAccount
    # Approve pool contract for token transfer
    # approve_pool(w3, pool, tok, balance)
    tx_hash = pool.functions.bind(tok.address, balance, dnorm).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    print(tx_hash.hex())
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)


def bind_pool():
    w3, contracts = connect()
    pool = contracts['SS_BPOOL']

    tokens = ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']

    weights = [50, 25, 25]

    prices = [1, 50, 50]

    amount_collateral = 1000

    for i in range(len(tokens)):
        tok_name = tokens[i]
        tok_wt = weights[i]
        tok_price = prices[i]
        # Denormalized weight needs to be in range 1e18 - 50e18 so rule of thumb
        # from Balancer Bankless article is use percentage divided by 2
        denorm_wt = int(tok_wt * 10**18 / 2)
        tok = contracts[tok_name]
        tok_decimals = tok.functions.decimals().call()
        tok_qty = int(tok_wt / 100 * amount_collateral / tok_price * (10 ** tok_decimals))
        tok_qty_unit = tok_qty / (10**tok_decimals)
        print(f'{tok_name}: weight {tok_wt} = {denorm_wt}, qty {tok_qty_unit} = {tok_qty}')
        bind_token(w3, pool=pool, tok=tok, balance=tok_qty, dnorm=denorm_wt)


def check_pool():
    w3, contracts = connect()
    pool = contracts['SS_BPOOL']

    tokens = ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']

    # Check token balances
    for token_name in tokens:
        wt = pool.functions.getNormalizedWeight(contracts[token_name].address).call() / 10**18
        print(f'{token_name} has weight {wt} in pool at {pool.address}')

    # tok.functions.transfer(dest_address, qty_unitless).transact({'from': acct, 'gas': 1_000_000})



def transfer_ctk(dest_address, qty, tok_name='COLLATERAL_TOKEN'):
    # Transfer funds from the admin to the specified destination address
    contract_names = [tok_name]
    w3, contract_details = connect(contract_names)
    tok = contract_details[tok_name]
    acct = w3.eth.defaultAccount
    decimals = tok.functions.decimals().call()

    admin_balance = w3.fromWei(w3.eth.getBalance(acct), 'ether')
    print(f'Admin has {admin_balance:0.5f} ETH')

    def print_balance(name, address):
        tok_balance = tok.functions.balanceOf(address).call()/ 10 ** decimals
        print(f'{name}: {tok_balance}')

    print('Before transfer')
    print_balance('Admin', w3.eth.defaultAccount)
    print_balance('Dest', dest_address)
    qty_unitless = int(qty * 10**decimals)
    tok_symbol = tok.functions.symbol().call()
    print(f'Transferring {qty} {tok_symbol} tokens ({qty_unitless} unitless) to {dest_address}')
    tok.functions.transfer(dest_address, qty_unitless).transact({'from': acct, 'gas': 1_000_000})


def handler(request):
    # Hook for cloud function version
    request_json = request.get_json(silent=True)
    qty = float(request_json['qty'])
    dest_address = request_json['address']
    tok_name = request_json['token']
    transfer_ctk(dest_address=dest_address, qty=qty, tok_name=tok_name)


if __name__ == '__main__':
    """
    Example usage:
    # Transfer tokens
    (feature-token) >> python setup_testnet_account.py -d 0x9e0b3Ed7FEB54523Bf037e20D237e1b375c8342F -q 100 -t SSSHORT -a transfer
    Admin has 1.65952 ETH
    Before transfer
    Admin: 8290.9999
    Dest: 0.0

    
    # Check balance
    (feature-token) >> python setup_testnet_account.py -d 0x9e0b3Ed7FEB54523Bf037e20D237e1b375c8342F -a balance
    Wallet address 0x9e0b3Ed7FEB54523Bf037e20D237e1b375c8342F
    COLLATERAL_TOKEN     (0x160574AcC16EBBe6e46FD4A35Ab370f2cA335324):  10000.0 USDT
    CULONG               (0xcA4A999Ac7f64B9dF74Ce40034ea283791A51A5c):      0.0 CULONG
    CUSHORT              (0x669cF563b614A328beC95B284a7edD403913351D):      0.0 CUSHORT
    SSLONG               (0x8DAcf3Dafa0243C4C219CC23f7A2dA84412042CF):    100.0 SSLONG
    SSSHORT              (0x2FA92E7352636D0dd7Cf32097600E50e1898Fb68):    100.0 SSSHORT

    """

    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--dest_address', '-d', dest='dest_address', default='',
        help='Destination address'
    )
    parser.add_argument(
        '--quantity', '-q', dest='qty', default=0,
        help='Quantity of collateral tokens to transfer (scaled)'
    )
    parser.add_argument(
        '--token', '-t', dest='token_name', default='COLLATERAL_TOKEN',
        help='Token to transfer, default COLLATERAL_TOKEN'
    )
    parser.add_argument(
        '--action', '-a', dest='action', default='balance',
        help='Action to perform: transfer, balance (default)'
    )

    args = parser.parse_args()
    if args.action == 'transfer':
        transfer_ctk(args.dest_address, float(args.qty), args.token_name)
    elif args.action == 'balance':
        print_balance(args.dest_address)
