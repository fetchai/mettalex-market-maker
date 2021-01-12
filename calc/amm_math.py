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


def calc_token_balance(x_c, x_o, w_c, w_o, k):
    """Calculate token balance to lie on curve such that
    k = invariant(x_c, x_t, x_o, w_c, 1 - w_c - w_o, w_o)
    Typically would plot x_t vs x_c varying with other parameters fixed

    :return: x_t: token balance e.g. long as function of:
    :param x_c: coin balance
    :param x_o: other token balance e.g. short
    :param w_c: weight coin
    :param w_o: other token weight
    :param k: curve invariant
    """
    return (k/(x_c**w_c)/(x_o**w_o))**(1/(1 - w_c - w_o))


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


def set_amm_state_orig(x_c, x_l, x_s, v, C, sF=0):
    """For fixed token balances calculate the weights needed to achieve a current token balances
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


def set_amm_state(x_c, x_l, x_s, v, C, sF=0):
    """For fixed token balances calculate the weights needed to achieve at zero imbalance
    L price = v*C, S price = (1-v)*C where C is the coin needed to mint 1 L + 1 S
    """

    # Weights
    if x_l == 0 or x_s == 0:
        w_c = 1
        w_l = 0
        w_s = 0
    else:
        denom = C*x_l*x_s - x_c*(v*(x_l - x_s) - x_l)
        w_c = x_c*(v*(x_l - x_s) - x_l)/denom
        w_l = v*C*x_l*x_s/denom
        w_s = (1 - v)*C*x_l*x_s/denom

    return [x_c, x_l, x_s, w_c, w_l, w_s]


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


# Actions that we can perform on state
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


def mint_redeem(state, a_c, coin_per_pair=100, rebalance=False, **kwargs):
    n_c_0, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0 = state
    if a_c >= 0:
        # Mint
        if n_c_0 < a_c:
            raise ValueError('Insufficent coin')
        n_c_1 = n_c_0 - a_c
        n_l_1 = n_l_0 + a_c / coin_per_pair
        n_s_1 = n_s_0 + a_c / coin_per_pair
        tok_out = a_c / coin_per_pair
    else:
        # Redeem
        r_c = -a_c
        if r_c > min(n_s_0, n_l_0):
            raise ValueError('Insufficent token')
        n_c_1 = n_c_0 + r_c * coin_per_pair
        n_l_1 = n_l_0 - r_c
        n_s_1 = n_s_0 - r_c
        tok_out = a_c * coin_per_pair

    avg_price = coin_per_pair / 2

    if rebalance:
        # Keep same spot price as original
        # set_amm_state(x_c, x_l, x_s, v, C)
        v = get_amm_spot_prices(state)[0] / coin_per_pair
        new_state = set_amm_state(n_c_1, n_l_1, n_s_1, v, coin_per_pair)
    else:
        new_state = [n_c_1, n_l_1, n_s_1, w_c_0, w_l_0, w_s_0]

    return new_state, tok_out, avg_price


def deposit_withdraw(
        state, a_c, coin_per_pair=100, oracle_price=50, deposit=True,
        rebalance=True, rebalance_type='oracle', token_fraction=0.5, **kwargs
):
    """

    :param state:
    :param a_c:
    :param coin_per_pair:
    :param oracle_price:
    :param rebalance:
    :param rebalance_type:
    :param token_fraction:
    :param kwargs:
    :return:
    """
    n_c_0, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0 = state
    amm_price = get_amm_spot_prices(state)[0]

    if deposit:
        # Deposit liquidity
        mid_state = mint_redeem(
            [n_c_0 + a_c, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0],
            a_c*token_fraction, coin_per_pair=coin_per_pair
        )[0]
        n_c_1, n_l_1, n_s_1, w_c_1, w_l_1, w_s_1 = mid_state
        tok_out = -a_c
    else:
        # Withdraw liquidity
        # Step 1 convert pairs back to collateral
        mid_state = mint_redeem(
            state, -a_c*token_fraction/coin_per_pair, coin_per_pair=coin_per_pair
        )[0]
        # Use subscript a, b, c, etc for internal calculations here
        n_c_a, n_l_1, n_s_1, w_c_1, w_l_1, w_s_1 = mid_state
        # Step 2 withdraw collateral, this will be from coin in pool
        # plus redeemed position tokens
        n_c_1 = n_c_a - a_c
        tok_out = a_c

    if rebalance:
        if rebalance_type == 'oracle':
            new_state = set_amm_state(
                n_c_1, n_l_1, n_s_1, v=oracle_price/coin_per_pair, C=coin_per_pair
            )
            avg_price = oracle_price
        elif rebalance_type == 'amm':
            new_state = set_amm_state(
                n_c_1, n_l_1, n_s_1,
                v=amm_price/coin_per_pair, C=coin_per_pair
            )
            avg_price = amm_price
        elif rebalance_type == 'weighted':
            if deposit:
                # Deposit - average oracle and amm prices
                # Approximation to exact price change needed to get spot
                # price correct after removing imbalance
                balance_0 = n_c_0 + min(n_s_0, n_l_0)*coin_per_pair
                balance_t = balance_0 + a_c
                amm_wt = balance_0/balance_t  # Existing liquidity weight
                oracle_wt = a_c/balance_t   # New liquidity weight
                v = (amm_price*amm_wt + oracle_price*oracle_wt)/coin_per_pair
            else:
                # Withdraw
                # WIP: need to amplify distance from spot price caused by imbalance
                # in order that reversing an imbalance trade returns to spot
                raise ValueError('Not implemented')
                # balance_0 = n_c_1 + min(n_s_1, n_l_1) * coin_per_pair
                # balance_1 = balance_0 - a_c
                # amm_wt = balance_1 / balance_0  # Existing liquidity weight
                # oracle_wt = balance_1 / balance_0  # New liquidity weight
                # v = max(min(((amm_price - oracle_price)*amm_wt + oracle_price)/coin_per_pair, 1.), 0.)
            new_state = set_amm_state(
                n_c_1, n_l_1, n_s_1,
                v=v,
                C=coin_per_pair
            )
            avg_price = amm_price*amm_wt + oracle_price*oracle_wt
        else:
            raise ValueError('Unknown rebalance type: ', rebalance_type)
    else:
        new_state = mid_state
        avg_price = get_amm_spot_prices(mid_state)[0]

    return new_state, tok_out, avg_price


def perform_action(action, s_0, a_c, coin_per_pair=100, **swap_params):
    """Uniform interface for performing actions on AMM state

    :param action:
    :param s_0:
    :param a_c:
    :param coin_per_pair:
    :param swap_params:
    :return:
    """
    if action == 'swap_from_coin':
        s_1, tok_out, avg_price = simple_swap_from_coin(s_0, a_c, coin_per_pair=coin_per_pair, **swap_params)
    elif action == 'swap_to_coin':
        s_1, tok_out, avg_price = simple_swap_to_coin(s_0, a_c, coin_per_pair=coin_per_pair, **swap_params)
    elif action == 'mint_redeem':
        # Copy from other notebook
        s_1, tok_out, avg_price = mint_redeem(s_0, a_c, coin_per_pair=coin_per_pair, **swap_params)
    elif action == 'deposit':
        s_1, tok_out, avg_price = deposit_withdraw(
            s_0, a_c, coin_per_pair=coin_per_pair, deposit=True, **swap_params)
    elif action == 'withdraw':
        s_1, tok_out, avg_price = deposit_withdraw(
            s_0, a_c, coin_per_pair=coin_per_pair, deposit=False, **swap_params)

    else:
        raise ValueError('Unknown action', action)
    return s_1, tok_out, avg_price


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


def plot_action(
        s_0, a_c, n_c_min=5000., n_c_max=20000.,
        action='swap_from_coin', coin_per_pair=100, normalize_y=False, **swap_params
):
    """Plot action performed on AMM as plot of token balances vs coin balance
    This is similar to an indifference curve plot in micro-economics

    :param s_0:
    :param a_c:
    :param n_c_min:
    :param n_c_max:
    :param action:
    :param coin_per_pair:
    :param swap_params:
    :return:
    """
    n_c_0, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0 = s_0
    spot_l_0, spot_s_0 = get_amm_spot_prices(s_0)

    s_1, tok_out, avg_price = perform_action(action, s_0, a_c, coin_per_pair=coin_per_pair, **swap_params)

    n_c_1, n_l_1, n_s_1, w_c_1, w_l_1, w_s_1 = s_1
    spot_l_1, spot_s_1 = get_amm_spot_prices(s_1)

    x = np.linspace(n_c_min, n_c_max, 100).reshape(-1, 1)

    initial_balance = 0  # n_c_0 + min(n_l_0, n_s_0) * coin_per_pair
    if normalize_y:
        y_norm = (initial_balance - x)/coin_per_pair
        n_s_0_n = n_s_0 - (initial_balance - n_c_0)/coin_per_pair
        n_l_0_n = n_l_0 - (initial_balance - n_c_0)/coin_per_pair
        n_s_1_n = n_s_1 - (initial_balance - n_c_1)/coin_per_pair
        n_l_1_n = n_l_1 - (initial_balance - n_c_1)/coin_per_pair
    else:
        y_norm = np.zeros_like(x)
        n_s_0_n = n_s_0
        n_l_0_n = n_l_0
        n_s_1_n = n_s_1
        n_l_1_n = n_l_1

    # Plot initial state
    k_0 = calc_balancer_invariant(*s_0)
    _ = plt.plot(x, calc_token_balance(x, n_s_0, w_c_0, w_s_0, k_0) - y_norm,
                 c='k', linestyle=':', alpha=0.2, label='Initial Invariant')
    _ = plt.plot(x, calc_token_balance(x, n_l_0, w_c_0, w_l_0, k_0) - y_norm,
                 c='k', linestyle=':', alpha=0.2)
    _ = plt.plot(n_c_0, n_l_0_n, markerfacecolor='k', marker='o', markeredgecolor='k', markersize=8, alpha=0.2)
    _ = plt.plot(n_c_0, n_s_0_n, markerfacecolor='w', marker='o', markeredgecolor='k', markersize=8, alpha=0.2)

    # Plot state movement
    if action != 'mint_redeem':
        x_move = np.linspace(float(min(n_c_0, n_c_1)), float(max(n_c_0, n_c_1)), 100).reshape(-1, 1)
        if normalize_y:
            y_norm_move = (initial_balance - x_move) / coin_per_pair
        else:
            y_norm_move = np.zeros_like(x_move)
        if n_l_1 != n_l_0:
            # Long swap
            _ = plt.plot(x_move, calc_token_balance(x_move, n_s_0, w_c_0, w_s_0, k_0) - y_norm_move,
                         c='k', linestyle='-', alpha=0.5, label='Swap')
            _ = plt.plot([n_c_0, n_c_1], [n_s_0_n, n_s_1_n], c='k', alpha=0.5)
        else:
            # Short swap
            _ = plt.plot(x_move, calc_token_balance(x_move, n_l_0, w_c_0, w_l_0, k_0) - y_norm_move,
                         c='k', linestyle='-', alpha=0.5, label='Swap')
            _ = plt.plot([n_c_0, n_c_1], [n_l_0_n, n_l_1_n], c='k', alpha=0.5)
    else:
        _ = plt.plot([n_c_0, n_c_1], [[n_l_0_n, n_s_0_n], [n_l_1_n, n_s_1_n]],
                     c='k', alpha=0.5, label='Mint/Redeem')

    # Plot invariant curves without rebalance of weights for final state
    _ = plt.plot(x, calc_token_balance(x, n_s_1, w_c_0, w_s_0, k_0) - y_norm,
                 c='k', linestyle='--', alpha=0.2, label='Intermediate Invariant')
    _ = plt.plot(x, calc_token_balance(x, n_l_1, w_c_0, w_l_0, k_0) - y_norm,
                 c='k', linestyle='--', alpha=0.2)

    # Plot final invariant after rebalance
    k_1 = calc_balancer_invariant(*s_1)
    _ = plt.plot(x, calc_token_balance(x, n_s_1, w_c_1, w_s_1, k_1) - y_norm,
                 c='k', linestyle='-', alpha=0.2, label='Final Invariant')
    _ = plt.plot(x, calc_token_balance(x, n_l_1, w_c_1, w_l_1, k_1) - y_norm,
                 c='k', linestyle='-', alpha=0.2)

    # Plot final state
    ax_l = plt.plot(n_c_1, n_l_1_n, markerfacecolor='k', marker='o',
                    markeredgecolor='k', markersize=12, alpha=0.5, label='Long', linestyle='none')
    ax_s = plt.plot(n_c_1, n_s_1_n, markerfacecolor='w', marker='o',
                    markeredgecolor='k', markersize=12, alpha=0.5, label='Short', linestyle='none')

    if normalize_y:
        _ = plt.plot(x, np.ones_like(x)*(n_c_0/coin_per_pair + min(n_l_0, n_s_0)),
                     linestyle='-.', c='k', alpha=0.2, label='Initial Balance')
    else:
        _ = plt.plot(x, ((n_c_0 + min(n_l_0, n_s_0)*coin_per_pair) - x)/coin_per_pair,
                     linestyle='-.', c='k', alpha=0.2, label='Initial Balance')

    norm_str = ' (normalized)' if normalize_y else ''
    _ = plt.title(
        f'Action: {action}{norm_str}\n'
        f'Tokens in: {a_c:0.2f}  Tokens out: {tok_out:0.2f}  Average Price: {avg_price:0.2f}\n'
        + f'Old balance: {n_c_0:0.2f} Coin  {n_l_0:0.2f} Long  {n_s_0:0.2f}  Short\n'
        + f'New balance: {n_c_1:0.2f} Coin  {n_l_1:0.2f} Long  {n_s_1:0.2f}  Short\n'
        + f'Old spot prices: Long {spot_l_0:0.2f}  Short {spot_s_0:0.2f}\n'
        + f'New spot prices: Long {spot_l_1:0.2f}  Short {spot_s_1:0.2f}\n'
    )
    _ = plt.xlabel('$n_c$')
    if normalize_y:
        _ = plt.ylabel('$n_l, n_s$ (normalized)')
    else:
        _ = plt.ylabel('$n_l, n_s$')
    _ = plt.legend()


    return s_1, tok_out, avg_price


def plot_orderbook(state, is_long=True, **plot_args):
    tok_ind = 1 if is_long else 2

    sell_volume = np.flip(np.linspace(float(state[tok_ind] / 1000.), float(state[tok_ind] / 2.), 20))
    sell_price = np.array(
        [perform_action('swap_to_coin', state, v, rebalance=False, from_long=is_long)[2]
         for v in sell_volume]
    )

    buy_volume = np.linspace(float(state[0] / 1000.), float(state[0] / 2.), 20)
    buy_price = np.array(
        [perform_action('swap_from_coin', state, v, rebalance=False, to_long=is_long)[2]
         for v in buy_volume]
    )

    _ = plt.plot(
        np.concatenate([sell_price, buy_price]),
        np.concatenate([sell_volume, buy_volume / buy_price]),
        **plot_args)


def plot_action_orderbook(
        s_0, a_c, n_c_min=5000, n_c_max=20000, action='swap_from_coin', coin_per_pair=100,
        xlim=None, ylim=None, **swap_params):
    n_c_0, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0 = s_0
    spot_l_0, spot_s_0 = get_amm_spot_prices(s_0)

    s_1, tok_out, avg_price = perform_action(action, s_0, a_c, coin_per_pair=coin_per_pair, **swap_params)

    n_c_1, n_l_1, n_s_1, w_c_1, w_l_1, w_s_1 = s_1
    spot_l_1, spot_s_1 = get_amm_spot_prices(s_1)

    # Plot initial state
    _ = plt.subplot(1, 2, 1)
    plot_orderbook(s_0, is_long=False, c='k', linestyle=':', alpha=0.2)
    plot_orderbook(s_1, is_long=False, c='k', linestyle='-', alpha=0.5)
    _ = plt.xlabel('Price')
    _ = plt.ylabel('Volume')
    _ = plt.title('Short')
    _ = plt.legend(['Initial', 'Final'])
    if xlim is not None:
        _ = plt.xlim(xlim)
    if ylim is not None:
        _ = plt.ylim(ylim)

    _ = plt.subplot(1, 2, 2)
    plot_orderbook(s_0, is_long=True, c='k', linestyle=':', alpha=0.2)
    plot_orderbook(s_1, is_long=True, c='k', linestyle='-', alpha=0.5)
    _ = plt.xlabel('Price')
    _ = plt.ylabel('Volume')
    _ = plt.title('Long')
    _ = plt.legend(['Initial', 'Final'])
    if xlim is not None:
        _ = plt.xlim(xlim)
    if ylim is not None:
        _ = plt.ylim(ylim)

    #     _ = plt.title(
    #         f'Tokens in: {a_c:0.2f}  Tokens out: {tok_out:0.2f}  Average Price: {avg_price:0.2f}\n'
    #         + f'Old balance: {n_c_0:0.2f} Coin  {n_l_0:0.2f} Long  {n_s_0:0.2f}  Short\n'
    #         + f'New balance: {n_c_1:0.2f} Coin  {n_l_1:0.2f} Long  {n_s_1:0.2f}  Short\n'
    #         + f'Old spot prices: Long {spot_l_0:0.2f}  Short {spot_s_0:0.2f}\n'
    #         + f'New spot prices: Long {spot_l_1:0.2f}  Short {spot_s_1:0.2f}\n'
    #     )
    #     _ = plt.xlabel('$n_c$')
    #     _ = plt.ylabel('$n_l, n_s$')
    #     _ = plt.legend()

    return s_1, tok_out, avg_price


def print_state_change(
        action, s_0, a_c, s_1=None, tok_out=None, avg_price=None,
        coin_per_pair=None, **action_params):
    n_c_0, n_l_0, n_s_0, w_c_0, w_l_0, w_s_0 = s_0
    spot_l_0, spot_s_0 = get_amm_spot_prices(s_0)

    if s_1 is None:
        s_1, tok_out, avg_price = perform_action(
            action, s_0, a_c, coin_per_pair=coin_per_pair, **action_params)

    n_c_1, n_l_1, n_s_1, w_c_1, w_l_1, w_s_1 = s_1
    spot_l_1, spot_s_1 = get_amm_spot_prices(s_1)

    print(
        f'Action: {action}\n'
        f'Tokens in: {a_c:0.2f}  Tokens out: {tok_out:0.2f}  Average Price: {avg_price:0.2f}\n'
        + f'Old balance {get_amm_balance(s_0):0.2f}: {n_c_0:0.2f} Coin  {n_l_0:0.2f} Long  {n_s_0:0.2f}  Short\n'
        + f'New balance {get_amm_balance(s_1):0.2f}: {n_c_1:0.2f} Coin  {n_l_1:0.2f} Long  {n_s_1:0.2f}  Short\n'
        + f'Old spot prices: Long {spot_l_0:0.2f}  Short {spot_s_0:0.2f}\n'
        + f'New spot prices: Long {spot_l_1:0.2f}  Short {spot_s_1:0.2f}\n')
    return s_1, tok_out, avg_price


def perform_action_sequence(initial_state, actions, reporter=None):
    print(get_amm_spot_prices(initial_state) + ['initial'])
    states = [initial_state]
    tok_outs = [0]
    avg_prices = [get_amm_spot_prices(initial_state)[0]]
    for action in actions:
        new_state, tok_out, avg_price = perform_action(
            action[0],
            states[-1],
            action[1], **action[2]
        )
        if reporter is None:
            print(get_amm_spot_prices(new_state) + action[:2])
        else:
            reporter(action[0], states[-1], action[1], new_state, tok_out, avg_price)
        states.append(new_state)
        tok_outs.append(tok_out)
        avg_prices.append(avg_price)
    return states, tok_outs, avg_prices
