import os
import json
from web3.middleware import construct_sign_and_send_raw_middleware
from pathlib import Path
from glob import glob
import argparse


def read_config(contracts=None, get_related=True):
    # Read configuration from local file system
    # For cloud function replace with reading from secrets manager
    contracts = contracts or [
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


def connect(contract_names=None, get_related=True):
    config, contract_details = read_config(
        contracts=contract_names, get_related=get_related
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


def print_token_balance(name, tok, holder_address):
    """Print token balance of specified address

    :param name: Name of token
    :param tok: Web3 token object
    :param holder_address: Address of token holder
    :return: None, prints balance
    """
    tok_address = tok.address
    tok_decimals = tok.functions.decimals().call()
    tok_balance = tok.functions.balanceOf(holder_address).call()/ 10 ** tok_decimals
    tok_symbol = tok.functions.symbol().call()
    print(f'{name:20} ({tok_address}): {tok_balance:8} {tok_symbol}')


def print_balance(w3, contracts, holder_address=None, tokens=None):
    """Print all token balances

    :param w3: Web3 connection
    :param contracts: dict of Web3 contracts
    :param holder_address: Address of token holder
    :param tokens: list of token names, default ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    :return: None, prints token balances
    """
    tokens = tokens or ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    holder_address = holder_address or w3.eth.defaultAccount
    eth_balance = w3.eth.getBalance(holder_address) / 10**18
    print(f'Wallet address {holder_address} ({eth_balance} ETH)')
    for token in tokens:
        tok = contracts[token]
        print_token_balance(token, tok, holder_address)


def deploy_pool(w3, contracts):
    """Deploy new autonomous market maker pool

    :param w3: Web3 connection
    :param contracts: dict of Web3 contracts
    :return: address of deployed Balancer pool
    """
    factory = contracts['BFACTORY']
    acct = w3.eth.defaultAccount
    tx_hash = factory.functions.newBPool().transact(
        {'from': acct, 'gas': 5_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    # Find pool address from contract event
    pool_address = factory.events.LOG_NEW_POOL().processReceipt(tx_receipt)[0]['args']['pool']
    print(f'New pool created at {pool_address}')
    return pool_address


def approve_pool(w3, pool, tok, balance):
    """Approve pool to transferFrom ERC20 token

    :param w3: Web3 connection
    :param pool: Web3 contract object for the AMM pool
    :param tok: Web3 contract object for the token
    :param balance: unitless balance to approve
    :return: None, prints amount approved
    """
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
    """Bind specified balance of token to AMM pool with specified weight

    :param w3: Web3 connection
    :param pool: Web3 contract for the AMM pool
    :param tok: Web3 contract for the token
    :param balance: unitless balance to transfer to pool
    :param dnorm: denormalized weight of the token in the pool
        Denormalized weight needs to be in range 1e18 - 50e18 so rule of thumb
        from Balancer Bankless article is use percentage divided by 2 times 10**18
    :return: None, prints transaction hash
    """
    acct = w3.eth.defaultAccount
    # Approve pool contract for token transfer
    approve_pool(w3, pool, tok, balance)
    tx_hash = pool.functions.bind(tok.address, balance, dnorm).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(tx_hash.hex())


def rebind_token(w3, pool, tok, balance, dnorm):
    """Rebind specified balance of existing pool token to specified weight

    :param w3: Web3 connection
    :param pool: Web3 contract for the AMM pool
    :param tok: Web3 contract for the token
    :param balance: unitless balance to keep in pool
    :param dnorm: denormalized weight of the token in the pool
        Denormalized weight needs to be in range 1e18 - 50e18 so rule of thumb
        from Balancer Bankless article is use percentage divided by 2 times 10**18
    :return: None, prints transaction hash
    """
    acct = w3.eth.defaultAccount
    # Approve pool contract for token transfer
    tx_hash = pool.functions.rebind(tok.address, balance, dnorm).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(tx_hash.hex())


def unbind_token(w3, pool, tok):
    """Remove token from pool and return to controller

    :param w3: Web3 connection
    :param pool: Web3 contract for the AMM pool
    :param tok: Web3 contract for the token
    :return: None, prints transaction hash
    """
    acct = w3.eth.defaultAccount
    tx_hash = pool.functions.unbind(tok.address).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print(tx_hash.hex())


def set_fee(w3, pool, fee=0.003):
    """Sets pool swap fee

    :param w3: Web3 connection
    :param pool: Web3 contract for the AMM pool
    :param fee: Swap fee, default 0.003 = 0.3%
    :return: None, prints old and new fees
    """
    acct = w3.eth.defaultAccount
    old_fee = (pool.functions.getSwapFee().call()) / 10**18 * 100
    tx_hash = pool.functions.setSwapFee(int(fee * 10**18)).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    new_fee = (pool.functions.getSwapFee().call()) / 10**18 * 100
    print(f'Pool at {pool.address} fee changed from {old_fee}% to {new_fee}%')


def bind_pool(
        w3, contracts,
        pool_name='SS_BPOOL', tokens=None,
        amount_collateral=1000, weights=None, prices=None
):
    """Main pool creation entrypoint: bind list of tokens with weights and balances

    :param w3: Web3
    :param contracts:
    :param pool_name:
    :param tokens:
    :param amount_collateral:
    :param weights:
    :param prices:
    :return:
    """
    pool = contracts[pool_name]

    tokens = tokens or ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    if weights is None:
        weights = [50, 25, 25]
    if prices is None:
        prices = [1, 50, 50]

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


def unbind_pool(w3, contracts, pool_name='SS_BPOOL', tokens=None):
    pool = contracts[pool_name]
    tokens = tokens or ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    for token in tokens:
        unbind_token(w3, pool, contracts[token])


def rebalance_weights(
        w3, contracts,
        price=0.5,
        # CPU for $100.000_000_000_000_000_000 (18 dp) = 1.000_000 mt (6 dp)
        collateral_per_unit=100_000_000_000_000,
        pool_name='SS_BPOOL', tokens=None
):
    pool = contracts[pool_name]
    tokens = tokens or ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    no_tokens = pool.functions.getNumTokens().call() == 0
    if no_tokens:
        print(f'Pool at {pool.address} has no tokens bound')
        return

    toks = [contracts[token] for token in tokens]

    w_c, w_l, w_s = [pool.functions.getDenormalizedWeight(tok.address).call() for tok in toks]
    x_c, x_l, x_s = [pool.functions.getBalance(tok.address).call() for tok in toks]

    # Number of collateral tokens per pair of long and short tokens
    v = price
    C = collateral_per_unit

    d = C*v*x_l + C*x_s*(1 - v) + x_c
    new_wts = [
        x_c/d,
        v*C*x_l/d,
        (1-v)*C*x_s/d
    ]

    new_denorm_wts = [int(100 * tok_wt * 10**18 / 2) for tok_wt in new_wts]

    balances = [x_c, x_l, x_s]

    wts = [w_c, w_l, w_s]

    # Need to apply new weights in increasing order of changes to avoid
    # total weight exceeding limit (ERR_MAX_TOTAL_WEIGHT in Solidity code)
    # i.e. apply negative weight changes first
    tok_inds = sorted(range(len(new_denorm_wts)), key=lambda k: new_denorm_wts[k] - wts[k])

    for i in tok_inds:
        tok_name = tokens[i]
        tok = toks[i]
        denorm_wt = new_denorm_wts[i]
        tok_qty = balances[i]
        delta = denorm_wt - wts[i]
        print(f'{tok_name}: weight {denorm_wt}, weight change {delta}, qty {tok_qty}')
        rebind_token(w3, pool=pool, tok=tok, balance=tok_qty, dnorm=denorm_wt)
    return wts, new_denorm_wts


def get_pool_balance(w3, contracts, pool_name='SS_BPOOL', tokens=None):
    pool = contracts[pool_name]
    # Early exit if no tokens
    no_tokens = pool.functions.getNumTokens().call() == 0
    if no_tokens:
        print(f'Pool at {pool.address} has no tokens bound')
        return

    tokens = tokens or ['COLLATERAL_TOKEN', 'SSLONG', 'SSSHORT']
    # Check token balances
    for token_name in tokens:
        tok = contracts[token_name]
        wt = pool.functions.getNormalizedWeight(contracts[token_name].address).call() / 10**18
        balance = pool.functions.getBalance(tok.address).call() / 10 ** (tok.functions.decimals().call())
        print(f'Pool at {pool.address} has {token_name} weight {wt} and balance {balance} ')


def get_spot_price(w3, pool, tok_in, tok_out, unitless=True, include_fee=True):
    """Get spot price for tok_out in terms of number of tok_in required to purchase

    :param w3: Web3 connection
    :param pool: Web3 contract for pool
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
        spot_price = pool.functions.getSpotPrice(
            tok_in.address, tok_out.address
        ).call()
    else:
        spot_price = pool.functions.getSpotPriceSansFee(
            tok_in.address, tok_out.address
        ).call()
    if not unitless:
        # Take decimals into account
        spot_price = spot_price * 10**(
                tok_out.functions.decimals().call()
                - tok_in.functions.decimals().call()
                - 18)
    return spot_price


def calc_out_given_in(w3, pool, tok_in, tok_out, qty_in, unitless=True):
    balance_in = pool.functions.getBalance(tok_in.address).call()
    wt_in = pool.functions.getDenormalizedWeight(tok_in.address).call()

    balance_out = pool.functions.getBalance(tok_out.address).call()
    wt_out = pool.functions.getDenormalizedWeight(tok_out.address).call()

    qty_in_unitless = int(qty_in * 10**(tok_in.functions.decimals().call()))

    fee = pool.functions.getSwapFee().call()

    out_tokens = pool.functions.calcOutGivenIn(
        balance_in, wt_in, balance_out, wt_out, qty_in_unitless, fee
    ).call()
    if not unitless:
        out_tokens /= 10**(tok_out.functions.decimals().call())
    return out_tokens


def set_public_swap(w3, pool, public=False):
    """Allow or disallow swaps with pool

    :param w3: Web3 connection
    :param pool: Web3 contract for pool
    :param public: boolean, set to True to allow swaps
    :return: pool public swap status
    """
    acct = w3.eth.defaultAccount
    tx_hash = pool.functions.setPublicSwap(public).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    return get_public_swap(w3, pool)


def get_public_swap(w3, pool):
    """Get public swap status of pool

    :param w3: Web3 connection
    :param pool: Web3 contract for pool
    :return: True if pool can be traded with
    """
    return pool.functions.isPublicSwap().call()


def swap_amount_in(w3, pool, tok_in, qty_in, tok_out, min_qty_out=None, max_price=None):
    acct = w3.eth.defaultAccount

    qty_in_unitless = int(qty_in * 10**(tok_in.functions.decimals().call()))

    if qty_in_unitless > tok_in.functions.allowance(acct, pool.address).call():
        approve_pool(w3, pool, tok_in, qty_in_unitless)

    if min_qty_out is None:
        # Default to allowing 10% slippage
        spot_price = get_spot_price(w3, pool, tok_in, tok_out, unitless=False)
        min_qty_out = qty_in / spot_price * 0.9
        print(f'Minimum output token quantity not specified: using {min_qty_out}')

    if max_price is None:
        spot_price_unitless = get_spot_price(w3, pool, tok_in, tok_out)
        max_price = int(spot_price_unitless * 1/0.9)
        print(f'Max price not specified: using {max_price}')

    min_qty_out_unitless = int(min_qty_out * 10**(tok_out.functions.decimals().call()))

    tx_hash = pool.functions.swapExactAmountIn(
        tok_in.address, qty_in_unitless,
        tok_out.address, min_qty_out_unitless,
        max_price
    ).transact(
        {'from': acct, 'gas': 1_000_000}
    )
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    return tx_hash


if __name__ == '__main__':
    """Example usage from console
    %load_ext autoreload
    %autoreload 2
    import os
    import sys
    os.chdir('price-leveraged-token/market-maker')
    sys.path.append(os.getcwd())
    from setup_testnet_pool import connect, print_balance, deploy_pool, bind_pool, bind_token, approve_pool, get_pool_balance, unbind_pool, set_fee, get_spot_price, swap_amount_in, set_public_swap, calc_out_given_in, rebalance_pool, get_public_swap
    w3, contracts = connect()
    get_pool_balance(w3, contracts)
    get_spot_price(w3, pool, ctok, stok, unitless=True, include_fee=False) 
    get_spot_price(w3, pool, ctok, stok, unitless=False, include_fee=False) 
    get_spot_price(w3, pool, ctok, ltok, unitless=False, include_fee=False) 
    rebalance_weights(w3, contracts, 0.4)  # Price is in fraction of cap - floor 
    """

    # Setup connections and variables in environment
    w3, contracts = connect()
    pool = contracts['SS_BPOOL']
    ctok = contracts['COLLATERAL_TOKEN']
    ltok = contracts['SSLONG']
    stok = contracts['SSSHORT']
