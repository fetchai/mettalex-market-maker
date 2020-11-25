import sympy as sp
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns


def calc_balancer_invariant(x_c, x_l, x_s, w_c, w_l, w_s):
    """
    calcBalancerInvariant - return invariant satisfied by Balancer pool for swaps
    Uses discrete inputs rather than state vector for ease of vectorized plotting use.
    To use state vector: calc_balancer_invariant(*state)
    """
    return (x_c**w_c)*(x_l**w_l)*(x_s**w_s)


def calc_spot_price(bI, wI, bO, wO, sF=0):
    """
    calcSpotPrice                                                                             //
     sP = spotPrice                                                                            //
     bI = tokenBalanceIn                ( bI / wI )         1                                  //
     bO = tokenBalanceOut         sP =  -----------  *  ----------                             //
     wI = tokenWeightIn                 ( bO / wO )     ( 1 - sF )                             //
     wO = tokenWeightOut                                                                       //
     sF = swapFee
    """
    return (bI/wI)/(bO/wO)/(1-sF)


def calc_out_given_in(bO, wO, bI, wI, aI, sF=0):
    """
    calcOutGivenIn                                                                            //
     aO = tokenAmountOut                                                                       //
     bO = tokenBalanceOut                                                                      //
     bI = tokenBalanceIn              /      /            bI             \    (wI / wO) \      //
     aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  | ^            |     //
     wI = tokenWeightIn               \      \ ( bI + ( aI * ( 1 - sF )) /              /      //
     wO = tokenWeightOut                                                                       //
     sF = swapFee
    """
    return bO*(1-(bI/(bI + (aI*(1-sF))))**(wI/wO))


def calc_in_given_out(bO, wO, bI, wI, aO, sF=0):
    """
    calcInGivenOut                                                                            //
     aI = tokenAmountIn                                                                        //
     bO = tokenBalanceOut               /  /     bO      \    (wO / wI)      \                 //
     bI = tokenBalanceIn          bI * |  | ------------  | ^            - 1  |                //
     aO = tokenAmountOut    aI =        \  \ ( bO - aO ) /                   /                 //
     wI = tokenWeightIn           --------------------------------------------                 //
     wO = tokenWeightOut                          ( 1 - sF )                                   //
     sF = swapFee
    """
    return bI*((bO/(bO - aO))**(wO/wI) - 1)/(1-sF)


def set_amm_state(x_c, x_l, x_s, v, C, sF=0):
    """For fixed token balances calculate the weights needed to achieve
    L price = v*C, S price = (1-v)*C where C is the coin needed to mint 1 L + 1 S
    """

    # Weights
    w_c, w_l, w_s = sp.symbols('w_c w_l w_s', positive=True)

    sol = sp.solve(
    [w_c + w_l + w_s - 1,   # Weights sum to 1
     calc_spot_price(x_c, w_c, x_l, w_l, sF) - v*C,      # Long token price = v*C
     calc_spot_price(x_c, w_c, x_s, w_s, sF) - (1-v)*C,  # Short token price = (1-v)*C
    ]
     , [w_c, w_l, w_s])
    return [x_c, x_l, x_s, sol[w_c], sol[w_l], sol[w_s]]


def set_amm_state_rebalance(C, sF=0):
    # Weights
    w_c, w_l, w_s = sp.symbols('w_c w_l w_s', positive=True)
    # Balances
    x_c, x_l, x_s = sp.symbols('x_c x_l x_s', positive=True)
    # Change in coin due to mint or redeem
    d_c = sp.symbols('{\Delta}x_c')
    # Constraints

    # Constraint 1: Weights sum to 1
    wt_sum = sp.Equality(w_c + w_l + w_s, 1)
    # Constraint 2: Sum of position token spot prices is collateral backing them
    price_sum = sp.Equality(
        calc_spot_price(x_c, w_c, x_l, w_l, sF) +
        calc_spot_price(x_c, w_c, x_s, w_s, sF),
        C
    )
    # Constraint 3: Mint of redeem position tokens in pairs
    mint_sum = x_c - d_c + x_l + d_c/C + x_s + d_c/C

    # Rebalance


def get_amm_spot_prices(state, sF=0):
    """Return L and S prices in units of coin
    """
    coin_ind = 0
    ltk_ind = 1
    stk_ind = 2
    n_tok = len(state) // 2
    ltk_price, stk_price = (
        calc_spot_price(
            state[coin_ind], state[coin_ind + n_tok],
            state[tok_ind], state[tok_ind + n_tok],
            sF) for tok_ind in [ltk_ind, stk_ind]
    )
    return [ltk_price, stk_price]


def get_amm_balance(state):
    spot_prices = get_amm_spot_prices(state)
    return state[0] + state[1]*spot_prices[0] + state[2]*spot_prices[1]


def simple_swap_from_coin(state, aI, to_long=True, sF=0, coin_per_pair=1,
                          rebalance=False, rebalance_fun=set_amm_state):
    """Swap a_c coins in for specified token (1=L, 2=S)
    """
    tok_ind = 1 if to_long else 2
    coin_ind = 0
    n_tok = len(state) // 2
    # calc_out_given_in(bO, wO, bI, wI, aI, sF=0)
    bO = state[tok_ind]
    wO = state[tok_ind + n_tok]
    bI = state[coin_ind]
    wI = state[coin_ind + n_tok]
    aO = calc_out_given_in(bO, wO, bI, wI, aI, sF)
    avg_price = aI / aO  # Price paid to AMM in coin for each position token
    if to_long:
        new_state = [
            state[0] + aI,
            state[1] - aO,
            state[2],
            state[3], state[4], state[5]
        ]
    else:
        new_state = [
            state[0] + aI,
            state[1],
            state[2] - aO,
            state[3], state[4], state[5]
        ]
    if rebalance:
        new_spot = get_amm_spot_prices(new_state)
        new_state = rebalance_fun(
            new_state[0], new_state[1], new_state[2],
            new_spot[0] / (new_spot[0] + new_spot[1]),
            coin_per_pair
        )

    return new_state, aO, avg_price


def simple_swap_to_coin(
        state, aI, from_long=True, sF=0,
        coin_per_pair=1, rebalance=False, rebalance_fun=set_amm_state):
    """Swap position tokens in for coin
    """
    tok_ind = 1 if from_long else 2
    coin_ind = 0
    n_tok = len(state) // 2
    # calc_out_given_in(bO, wO, bI, wI, aI, sF=0)
    bO = state[coin_ind]
    wO = state[coin_ind + n_tok]
    bI = state[tok_ind]
    wI = state[tok_ind + n_tok]
    aO = calc_out_given_in(bO, wO, bI, wI, aI, sF)
    avg_price = aO / aI  # Price in coin paid for input position token
    if from_long:
        new_state = [
            state[0] - aO,
            state[1] + aI,
            state[2],
            state[3], state[4], state[5]
        ]
    else:
        new_state = [
            state[0] - aO,
            state[1],
            state[2] + aI,
            state[3], state[4], state[5]
        ]
    if rebalance:
        new_spot = get_amm_spot_prices(new_state)
        new_state = rebalance_fun(
            new_state[0], new_state[1], new_state[2],
            new_spot[0] / (new_spot[0] + new_spot[1]),
            coin_per_pair
        )

    return new_state, aO, avg_price


def simulate_swaps_from_coin(x_c_0, x_l_0, x_s_0, v, C, from_coin=True, c_max=1000, n_row=1, offset=0, f=None):
    initial_state = set_amm_state(x_c_0, x_l_0, x_s_0, v, C)

    coin_in_short = np.linspace(-c_max, 1., 20)
    coin_in_long = np.linspace(1., c_max, 20)
    # Swap coin for short
    states_short, coin_out_short, avg_price_short = zip(
        *[simple_swap_from_coin(initial_state, -t, coin_per_pair=100, rebalance=True, to_long=False)
          for t in coin_in_short])

    # Swap coin for long
    states_long, coin_out_long, avg_price_long = zip(
        *[simple_swap_from_coin(initial_state, t, coin_per_pair=100, rebalance=True)
          for t in coin_in_long])

    coin_in = np.concatenate([coin_in_short, coin_in_long])
    states = np.concatenate([np.array(states_short), np.array(states_long)])
    # coin_out = [] + coin_out_short + coin_out_long
    avg_price = np.concatenate([np.array(avg_price_short), np.array(avg_price_long)])

    # # No rebalancing, raw C-> L (or C->S) swap
    # states_raw, tok_out_raw, avg_price_raw = zip(
    #     *[simple_swap_from_coin(initial_state, c, coin_per_pair=100, rebalance=False) for c in coin_in])

    if n_row == 1 and not f:
        _ = plt.figure(figsize=(10, 4))
    # Pool balance

    balances = np.array([get_amm_balance(s) for s in states])
    # balances_raw = np.array([get_amm_balance(s) for s in states_raw])

    _ = plt.subplot(n_row, 2, 1 + 2 * offset)
    _ = plt.plot(coin_in, balances)
    #     _ = plt.plot(coin_in, balances_raw, linestyle='--')
    _ = plt.legend(['With Rebalance',
                    #                     'No Rebalance'
                    ])
    _ = plt.title(f'Spot Price = {v}')
    _ = plt.xlabel('Coin In')
    _ = plt.ylabel('Pool balance')

    _ = plt.subplot(n_row, 2, 2 + 2 * offset)
    spot_prices = np.array([get_amm_spot_prices(s) for s in states])
    _ = plt.plot(coin_in, spot_prices)
    _ = plt.plot(coin_in, np.sum(spot_prices, axis=1), alpha=0.5)
    _ = plt.plot(coin_in, avg_price, alpha=0.2, c='k', linestyle=':')
    _ = plt.legend(['Long', 'Short', 'Long + Short', 'CoinIn/TokOut'])
    _ = plt.xlabel('Coin In')
    _ = plt.ylabel('Spot Price')

