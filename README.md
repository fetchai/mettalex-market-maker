# Autonomous Market Maker
On-chain market maker to allow traders to enter/exit a single-sided position without going through
the "mint pair and sell one side" flow.

The market maker itself is a private [Balancer](https://github.com/balancer-labs/balancer-core.git) pool
that is rebalanced to set position token prices in line with the underlying asset price.

A separate Pool Controller contract is used for supplying tokens to the Balancer pool (WIP).


# Implementation
The `setup_testnet_pool.py` file is the initial piece of work for testing using the 
Balancer Factory contract on Kovan to deploy a new Balancer pool.  
Testing has been via Python console to interact with the deployed pool.
For example:

    from setup_testnet_pool import (
        connect, print_balance, deploy_pool, bind_pool, 
        bind_token, approve_pool, get_pool_balance, 
        unbind_pool, set_fee, get_spot_price, 
        swap_amount_in, set_public_swap, calc_out_given_in, 
        rebalance_weights, get_public_swap
    )
    w3, contracts = connect()
    pool = contracts['SS_BPOOL']
    ctok = contracts['COLLATERAL_TOKEN']
    ltok = contracts['SSLONG']
    stok = contracts['SSSHORT']
    unbind_pool(w3, contracts)
    bind_pool(w3, contracts)
    get_pool_balance(w3, contracts)
    get_spot_price(w3, pool, ctok, ltok, unitless=False, include_fee=False) 
    rebalance_weights(w3, contracts, 0.4)
    get_spot_price(w3, pool, ctok, ltok, unitless=False, include_fee=False) 
