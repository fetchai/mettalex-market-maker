import sympy as sp
import numpy as np


def define_symbols():
    w_c, w_l, w_s = sp.symbols('w_c w_l w_s', positive=True)
    # Token balances
    x_c, x_l, x_s = sp.symbols('x_c x_l x_s', positive=True)
    # Prices - in units of locked up collateral
    # i.e. spot price = price_floor + (price_cap - price_floor)*v = price_floor + C*v
    v = sp.symbols('v', positive=True)  # Spot price in range floor to cap
    C = sp.symbols('C', positive=True)  # Collateral per pair in units of x_c

    # Swap fee in fraction of input tokens
    s_f = sp.symbols('s_f')

    # Input token amounts for swaps
    d_c, d_l, d_s = sp.symbols('{\Delta}x_c {\Delta}x_l {\Delta}x_s', real=True)
    return x_c, x_l, x_s, w_c, w_l, w_s, v, C, d_c, d_l, d_s


def define_equations(x_c, x_l, x_s, w_c, w_l, w_s, v, C, d_c, d_l, d_s):
    # Token Prices
    p_l, p_s = sp.symbols('p_l p_s', positive=True)

    pool_total = x_c + x_l * p_l + x_s * p_s
    price_sum = p_l + p_s

    swap_invariant = (x_c**w_c)*(x_l**w_l)*(x_s**w_s)
    swap_constraint = sp.Eq(
        swap_invariant,
        swap_invariant.subs(
            {x_c: x_c + d_c, x_l: x_l + d_l, x_s: x_s + d_s}
        )
    )

    # Constraint 1: sum of weights is 1
    weight_sum_constraint = sp.Equality(w_c + w_l + w_s, 1)

    # Constraint 2: sum of prices is C
    price_sum_constraint = sp.Eq(price_sum, C)

    # Constraint 3: relationship between w_l and long price
    weight_long_constraint = sp.Eq(p_l*x_l/pool_total, w_l)

    # Constraint 4: relationship between w_s and short price
    weight_short_constraint = sp.Eq(p_s * x_s / pool_total, w_s)

    # Constraint 5: long/short price ratio at equal x_l and x_s balance
    price_ratio_constraint_limit = sp.Eq(sp.Limit(p_l / p_s, x_s, x_l), v / (1 - v))

    # Solving for prices and weights
    prices = sp.solve([weight_long_constraint, weight_short_constraint], [p_l, p_s])

    price_ratio_constraint = sp.Eq(
        price_ratio_constraint_limit.lhs.subs(prices).doit(), price_ratio_constraint_limit.rhs)

    # Original form of weights solved for p_l/p_s = v/(1-v) when x_l = x_s
    weights_spec = sp.solve(
        [price_sum_constraint.subs(prices),
         price_ratio_constraint.subs(prices),
         weight_sum_constraint], [w_c, w_l, w_s], dict=True)[0]

    # Possible general form of weights for w_l/w_s = v/(1-v)*x_s/x_l
    weights_gen = sp.solve(
        [price_sum_constraint.subs(prices),
         sp.Eq(w_l/w_s, v/(1-v) * x_s/x_l),  # Correct price-weight relationship?
         weight_sum_constraint], [w_c, w_l, w_s], dict=True)[0]

    return weights_spec, swap_constraint


def define_uniswap_equations(x_g, x_m, w_g, w_m, d_g, d_m):
    # Token Prices
    p_g = sp.symbols('p_g', positive=True)

    pool_total = x_m + x_g*p_g

    swap_invariant = (x_g**w_g)*(x_m**w_m)
    swap_constraint = sp.Eq(
        swap_invariant,
        swap_invariant.subs(
            {x_g: x_g + d_g, x_m: x_m + d_m}
        )
    )

    # Constraint 1: sum of weights is 1
    weight_sum_constraint = sp.Equality(w_g + w_m, 1)

    # # Constraint 2: relationship between w_g and governance token price
    # weight_governance_constraint = sp.Eq(p_g*x_g/pool_total, w_g)
    #
    # # Solving for prices and weights
    # prices = sp.solve([weight_governance_constraint], [p_g])

    weights_spec = sp.solve(
        [weight_sum_constraint], [w_g, w_m], dict=True)[0]

    return weights_spec, swap_constraint


def define_uniswap_deposit_single():
    symbols = sp.symbols(
        'x_m x_g w_m w_g d_m d_g a_m a_g', positive=True
    )

    x_m, x_g, w_m, w_g, d_m, d_g, a_m, a_g = symbols
    swap_invariant = (x_m**w_m)*(x_g**w_g)
    swap_constraint = sp.Eq(
        swap_invariant,
        swap_invariant.subs(
            {x_g: x_g - d_g, x_m: x_m + d_m}
        )
    )
    deposit_money_constraint = sp.Eq(
        (a_m - d_m)*(x_g - d_g),
        (x_m + d_m)*d_g
    )

    deposit_gov_constraint = sp.Eq(
        (a_g - d_g)*(x_m - d_m),
        (x_g + d_g)*d_m
    )

    # Solve for decrease in governance tokens
    # sol = {d_g: sp.solve(deposit_money_constraint, d_g)[0].simplify()}
    # Result:
    sol_m_to_g = {d_g: x_g*(a_m - d_m)/(a_m + x_m)}

    # Then solve for swap constraint subbing in this solution for d_g
    # sol_d_m = sp.solve(swap_constraint.subs(sol_m_to_g), d_m)[0].simplify()
    # Result:
    sol_d_m = -x_m + (x_m ** w_m * (a_m + x_m) ** w_g) ** (1 / (w_g + w_m))

    # Could also solve for swap governance to money
    # sol_g_to_m = {d_m: sp.solve(deposit_gov_constraint, d_m)[0].simplify()}
    # Result:
    sol_g_to_m = {d_m: x_m*(a_g - d_g)/(a_g + x_g)}
    # sol_d_g = sp.solve(swap_constraint.subs({d_m: -d_m, d_g: -d_g}).subs(sol_g_to_m), d_g)[0].simplify()
    # Result:
    sol_d_g = -x_g + (x_g**w_g*(a_g + x_g)**w_m)**(1/(w_g + w_m))

    return sol_d_m, sol_d_g, symbols


class Swap(object):
    def __init__(
            self, tok_in, amount_in, tok_out, amount_out,
            initial_spot, trade_price, post_trade_spot, final_spot=None, fair_price=None,
            name=None
    ):
        self.tok_in = tok_in
        self.amount_in = amount_in
        self.tok_out = tok_out
        self.amount_out = amount_out
        self.initial_spot = initial_spot
        self.trade_price = trade_price
        self.post_trade_spot = post_trade_spot
        self.final_spot = final_spot
        self.fair_price = fair_price  # Price if no imbalance
        self.name = name

    def __repr__(self):
        out_str = ''
        if self.name is not None:
            out_str += f'{self.name}: '
        out_str += f'Trade {self.amount_in:0.2f} {self.tok_in} '
        out_str += f'for {self.amount_out:0.2f} {self.tok_out} '
        out_str += f'at initial spot {self.initial_spot:0.2f} '
        if self.fair_price is not None:
            out_str += f'(-fair price = {self.initial_spot - self.fair_price:0.2f}), '
        out_str += f'trade price {self.trade_price:0.2f}, '
        out_str += f'post-trade spot {self.post_trade_spot:0.2f}'
        if self.final_spot is not None:
            out_str += f', final spot {self.final_spot:0.2f}'
        return out_str


class AMM(object):
    def __init__(self, tokens=None, weights=None, price=None, collateral=None, token_names=None):
        self.symbols = define_symbols()
        self.tokens = tokens  # [x_c, x_l, x_s]
        self.cumulative_tokens = [0, 0, 0]
        self.weights = weights  # [w_c, w_l, w_s]
        self.price = price
        self.collateral = collateral
        # Default token names, can replace with market specific
        self._token_names = token_names or ['coin', 'long', 'short']
        self.weight_update = None
        self.swap_update = None
        self.lp_tokens = None
        self.swaps = []

    def set_weight_functions(self, weights):
        x_c, x_l, x_s, w_c, w_l, w_s, v, C, d_c, d_l, d_s = self.symbols

        wt_fns = np.array(
            [sp.lambdify(
                [x_c, x_l, x_s, v, C],
                weights[wt], 'numpy'
            ) for wt in [w_c, w_l, w_s]]
        )

        def update_fun(tokens, price, collateral):
            new_weights = [
                wt_fn(tokens[0], tokens[1], tokens[2], price, collateral)
                for wt_fn in wt_fns
            ]
            return new_weights
        self.weight_update = update_fun

    def set_swap_function(self, swap_cons):
        # symbols = [d_c, d_l, d_s]
        x_c, x_l, x_s, w_c, w_l, w_s, v, C, d_c, d_l, d_s = self.symbols
        common_symbols = [x_c, x_l, x_s, w_c, w_l, w_s]

        def get_sol(d_const, d_var, d_sol):
            # Get solution for trade holding one token constant, variable in of another
            # and solve for output number of tokens of last token
            return {
                'var': d_var,
                'fun': sp.solve(swap_cons.subs({d_const: 0}), d_sol)[0]
            }

        swap_sols = {
            (self.coin_name, self.long_name): get_sol(d_s, d_c, d_l),
            (self.coin_name, self.short_name): get_sol(d_l, d_c, d_s),
            (self.long_name, self.coin_name): get_sol(d_s, d_l, d_c),
            (self.short_name, self.coin_name): get_sol(d_l, d_s, d_c),
            # Direct swaps between position tokens
            (self.long_name, self.short_name): get_sol(d_c, d_l, d_s),
            (self.short_name, self.long_name): get_sol(d_c, d_s, d_l),
        }

        swap_funs = {
            k: sp.lambdify(
                common_symbols + [v['var']], v['fun'], 'numpy'
            ) for k, v in swap_sols.items()
        }
        # swap_funs = {
        #     ('coin', 'long'): sp.lambdify(
        #         common_symbols + [d_c], swap_sols[('coin', 'long')], 'numpy'
        #     ),
        #     ('coin', 'short'): sp.lambdify(
        #         common_symbols + [d_c], swap_sols[('coin', 'short')], 'numpy'
        #     ),
        #     ('long', 'coin'): sp.lambdify(
        #         common_symbols + [d_l], swap_sols[('long', 'coin')], 'numpy'
        #     ),
        #     ('short', 'coin'): sp.lambdify(
        #         common_symbols + [d_s], swap_sols[('short', 'coin')], 'numpy'
        #     ),
        # }

        self.swap_update = swap_funs

    def get_amount_out(self, tok_in, amount_in, tok_out):
        # Swap amount_in tok_in for x tok_out
        x_c, x_l, x_s = self.tokens
        w_c, w_l, w_s = self.weights
        return -self.swap_update[(tok_in, tok_out)](x_c, x_l, x_s, w_c, w_l, w_s, amount_in)

    def get_amount_in(self, tok_in, amount_out, tok_out):
        # Swap x tok_in for amount_out tok_out
        return -self.get_amount_out(tok_out, -amount_out, tok_in)

    @property
    def coin_name(self):
        return self.token_names[0]

    @property
    def long_name(self):
        return self.token_names[1]

    @property
    def short_name(self):
        return self.token_names[2]

    @property
    def _token_map(self):
        return dict(
            zip(
                ['coin', 'long', 'short'],
                self._token_names
            )
        )

    @property
    def token_names(self):
        return list(self._token_map.values())

    def name_lookup(self, tok):
        return self._token_map[tok]

    def spot_price(self, tok):
        return {
            self.long_name: self.weights[1] / self.weights[0] * self.tokens[0] / self.tokens[1],
            self.short_name: self.weights[2] / self.weights[0] * self.tokens[0] / self.tokens[2],
        }[tok]

    def trade_price(self, tok_in, amount_in, tok_out):
        amount_out = self.get_amount_out(tok_in, amount_in, tok_out)
        return amount_in/amount_out if tok_in == self.coin_name else amount_out/amount_in

    def trade_price_out(self, tok_in, amount_out, tok_out):
        amount_in = self.get_amount_in(tok_in, amount_out, tok_out)
        return amount_in/amount_out if tok_in == self.coin_name else amount_out/amount_in

    def swap(self, tok_in, amount_in, tok_out, reweight=True, report=False):
        amount_out = self.get_amount_out(tok_in, amount_in, tok_out)
        ind_in = self.token_names.index(tok_in)
        ind_out = self.token_names.index(tok_out)
        if not isinstance(amount_out, sp.Expr) and amount_out > self.tokens[ind_out]:
            raise ValueError('Not enough balance to trade')
        else:
            if report:
                print(self)
            tok_pos = tok_in if tok_in in {self.long_name, self.short_name} else tok_out
            initial_spot = self.spot_price(tok_pos)
            trade_price = self.trade_price(tok_in, amount_in, tok_out)
            self.tokens[ind_out] -= amount_out
            self.tokens[ind_in] += amount_in
            post_trade_spot = self.spot_price(tok_pos)
        if reweight:
            self.reweight()
        final_spot = self.spot_price(tok_pos)
        # Fair value price of token in absence of imbalance
        fair_price = self.price * self.collateral
        if self.short_name in {tok_in, tok_out}:
            fair_price = self.collateral - fair_price
        swap = Swap(tok_in, amount_in, tok_out, amount_out,
                    initial_spot, trade_price, post_trade_spot, final_spot, fair_price,
                    name='DEX')
        self.cumulative_tokens[ind_in] += amount_in
        self.cumulative_tokens[ind_out] -= amount_out
        if report:
            print(swap)
            print(self)

        self.swaps.append(swap)
        return swap

    def swap_out(self, tok_in, amount_out, tok_out, reweight=True, report=False):
        # Specify amount of tok_out we want to receive and calculate amount in
        # By symmetry we can get the amount of tokens out for the reverse swap
        # then use this for the amount in
        amount_in = self.get_amount_in(tok_in, amount_out, tok_out)
        return self.swap(tok_in, amount_in, tok_out, reweight=reweight, report=report)

    def reweight(self, price=None, report=False):
        if price is not None:
            self.price = price
        self.weights = self.weight_update(self.tokens, self.price, self.collateral)
        if self.lp_tokens is None:
            self.lp_tokens = self.total_value
        if report:
            print(self)

    @property
    def lp_price(self):
        return self.total_value / self.lp_tokens

    def rebase(self, lp_price=1):
        self.lp_tokens = self.total_value / lp_price

    @property
    def total_value(self):
        # Value of pool in coin
        return self.tokens[0] / self.weights[0]

    @property
    def invariant(self):
        k = 1
        for i in range(len(self.tokens)):
            k *= self.tokens[i]**self.weights[i]
        return k

    def get_state(self):
        total_value = self.total_value
        p_l = self.spot_price(self.long_name)
        p_s = self.spot_price(self.short_name)
        x_c, x_l, x_s = self.tokens
        return [total_value, x_c, x_l, p_l, x_s, p_s]

    def get_trade_balance_sheet(self):
        # Running total of coin paid to AMM (assets) and position tokens sold (liabilities)
        # Max liability for each position token sold is the full underlying collateral value
        # e.g. selling 1 Long token for 0.1 C can incur a liability of 1 C in the event of a cap
        # breach
        return self.assets, self.liabilities

    @property
    def assets(self):
        return self.cumulative_tokens[0]

    @property
    def liabilities(self):
        # Each position token can claim close to the entire collateral amount backing a pair
        # in the worst case, e.g. if there is a swing from floor to cap and S holders
        # exit near the floor, long holders exit near the cap.
        return -(self.cumulative_tokens[1] + self.cumulative_tokens[2])*self.collateral

    @property
    def equity(self):
        return self.assets - self.liabilities

    @property
    def safe_balance(self):
        total_value, x_c, x_l, p_l, x_s, p_s = self.get_state()
        try:
            x_p = min(x_l, x_s)
        except TypeError as ex:
            # Symbolic, assume x_l < x_s mainly for printing
            x_p = x_l
        _safe_balance = (p_l * x_p + p_s * x_p + x_c)  # coin and paired positions
        return _safe_balance

    @property
    def unsafe_balance(self):
        return self.total_value - self.safe_balance  # imbalance

    def __repr__(self):
        if self.weights is None:
            out_str = 'AMM weights not set.  Define weight function and reweight'
        else:
            total_value, x_c, x_l, p_l, x_s, p_s = self.get_state()
            # x_p = min(x_l, x_s)
            safe_balance = self.safe_balance  # coin and paired positions
            unsafe_balance = self.unsafe_balance  # imbalance
            if isinstance(total_value, sp.Expr):
                out_str = f'AMM Balance: {total_value.simplify()}'
                out_str += f'\n = {safe_balance.simplify()} (safe) + {unsafe_balance.simplify()} (risk)'
                out_str += f'\n = {x_c} {self.name_lookup("coin")}'
                out_str += f'\n    + {x_l} {self.name_lookup("long")} @ price {p_l.simplify()}'
                out_str += f'\n      (value {(x_l * p_l).simplify()})'
                out_str += f'\n    + {x_s} {self.name_lookup("short")} @ price {p_s.simplify()}'
                out_str += f'\n      (value {(x_s * p_s).simplify()})'
                out_str += f'\n'
                out_str += f'  Cumulative Trades:  Assets {self.assets}  Maximum Liabilities {self.liabilities}'
                out_str += '\n'
                out_str += f'  Trade Equity: {self.equity}'
                out_str += '\n'
                out_str += f'  LP Token Price: {self.lp_price}'
            else:            
                out_str = f'AMM Balance: {total_value:0.2f}'
                out_str += f'\n = {safe_balance:0.2f} (safe) + {unsafe_balance:0.2f} (risk)'
                out_str += f'\n = {x_c:0.2f} {self.name_lookup("coin")}'
                out_str += f' + {x_l:0.2f} {self.name_lookup("long")} @ {p_l:0.2f} ({x_l*p_l:0.2f})'
                out_str += f' + {x_s:0.2f} {self.name_lookup("short")} @ {p_s:0.2f} ({x_s*p_s:0.2f})'
                out_str += f'\n'
                out_str += f'  Cumulative Trades:  Assets {self.assets:0.2f}  Maximum Liabilities {self.liabilities:0.2f}'
                out_str += '\n'
                out_str += f'  Trade Equity: {self.equity:0.2f}'
                out_str += '\n'
                out_str += f'  LP Token Price: {self.lp_price:0.2f}'
        # out_str += f'       : {total_value:0.2f} = '
        return out_str


class UniswapPool:
    def __init__(self, tokens=None, weights=None, token_names=None):
        # Pool contains Money (m) and Governance (g) tokens
        # NB: we use a different symbol for the Coin (c) token used in main AMM
        # to allow e.g. use of LP tokens from this pool to act as Coin
        self.tokens = tokens
        self.weights = weights or [0.5, 0.5]
        self._token_names = token_names or ['money', 'gov']

        self.symbols = (
                sp.symbols('x_m x_g w_m w_g', positive=True) +
                sp.symbols('d_m d_g', real=True)
        )
        self.swap_update = None
        self.lp_tokens = self.tokens[0]**self.weights[0]*self.tokens[1]**self.weights[1]

        _, swap_constraint = define_uniswap_equations(*self.symbols)
        # self.set_weight_functions(weights)
        self.set_swap_function(swap_constraint)

    @property
    def money_name(self):
        return self.token_names[0]

    @property
    def gov_name(self):
        return self.token_names[1]

    @property
    def _token_map(self):
        return dict(
            zip(
                ['money', 'gov'],
                self._token_names
            )
        )

    @property
    def token_names(self):
        return list(self._token_map.values())

    def name_lookup(self, tok):
        return self._token_map[tok]

    def set_swap_function(self, swap_cons):
        # symbols = [d_c, d_l, d_s]
        x_m, x_g, w_m, w_g, d_m, d_g = self.symbols
        common_symbols = [x_m, x_g, w_m, w_g]

        def get_sol(d_var, d_sol):
            # Get solution for trade known amount of first token
            # and solve for output number of tokens of second token
            return {
                'var': d_var,
                'fun': sp.solve(swap_cons, d_sol)[0]
            }

        swap_sols = {
            (self.money_name, self.gov_name): get_sol(d_m, d_g),
            (self.gov_name, self.money_name): get_sol(d_g, d_m),
        }

        swap_funs = {
            k: sp.lambdify(
                common_symbols + [v['var']], v['fun'], 'numpy'
            ) for k, v in swap_sols.items()
        }
        self.swap_update = swap_funs

    def get_amount_out(self, tok_in, amount_in, tok_out):
        # Swap amount_in tok_in for x tok_out
        x_m, x_g = self.tokens
        w_m, w_g = self.weights
        return -self.swap_update[(tok_in, tok_out)](x_m, x_g, w_m, w_g, amount_in)

    def get_amount_in(self, tok_in, amount_out, tok_out):
        # Swap x tok_in for amount_out tok_out
        return -self.get_amount_out(tok_out, -amount_out, tok_in)

    def spot_price(self, tok=None):
        tok = tok or self.gov_name
        return {
            self.gov_name: self.weights[1] / self.weights[0] * self.tokens[0] / self.tokens[1],
        }[tok]

    def swap(self, tok_in, amount_in, tok_out=None, report=False):
        tok_out = tok_out or (
            self.money_name if (tok_in == self.gov_name) else self.gov_name
        )
        amount_out = self.get_amount_out(tok_in, amount_in, tok_out)
        ind_in = self.token_names.index(tok_in)
        ind_out = self.token_names.index(tok_out)
        if amount_out > self.tokens[ind_out]:
            raise ValueError('Not enough balance to trade')
        else:
            if report:
                print(self)
            tok_gov = tok_in if tok_in in {self.gov_name} else tok_out
            initial_spot = self.spot_price(tok_gov)
            trade_price = self.trade_price(tok_in, amount_in, tok_out)
            self.tokens[ind_out] -= amount_out
            self.tokens[ind_in] += amount_in
            post_trade_spot = self.spot_price(tok_gov)
        swap = Swap(tok_in, amount_in, tok_out, amount_out,
                    initial_spot, trade_price, post_trade_spot,
                    final_spot=None, fair_price=None, name='Uniswap Pool')
        if report:
            print(swap)
            print(self)

        return swap

    def swap_out(self, tok_in, amount_out, tok_out, report=False):
        # Specify amount of tok_out we want to receive and calculate amount in
        # By symmetry we can get the amount of tokens out for the reverse swap
        # then use this for the amount in
        amount_in = self.get_amount_in(tok_in, amount_out, tok_out)
        return self.swap(tok_in, amount_in, tok_out, report=report)

    def trade_price(self, tok_in, amount_in, tok_out):
        amount_out = self.get_amount_out(tok_in, amount_in, tok_out)
        return amount_in/amount_out if tok_in == self.money_name else amount_out/amount_in

    def trade_price_out(self, tok_in, amount_out, tok_out):
        amount_in = self.get_amount_in(tok_in, amount_out, tok_out)
        return amount_in/amount_out if tok_in == self.money_name else amount_out/amount_in

    @property
    def lp_price(self):
        return self.total_value / self.lp_tokens

    def rebase(self, lp_price=1):
        self.lp_tokens = self.total_value / lp_price

    def get_swap_for_deposit(self, amount_m=None, amount_g=None):
        # Determine how much of money to swap for gov to LP at correct ratio
        # or gov -> money
        # TODO: allow mix of tokens and determine target ratio
        sol_d_m, sol_d_g, symbols = define_uniswap_deposit_single()
        x_m, x_g, w_m, w_g, d_m, d_g, a_m, a_g = symbols
        state = {
            x_m: self.tokens[0],
            x_g: self.tokens[1],
            w_m: self.weights[0],
            w_g: self.weights[1],
        }
        if amount_m is not None and amount_g is None:
            state[a_m] = amount_m
            m_in = sol_d_m.subs(state)
            g_in = 0
        elif amount_g is not None and amount_m is None:
            state[a_g] = amount_g
            m_in = 0
            g_in = sol_d_g.subs(state)
        else:
            raise ValueError('Specify amount of money or gov tokens but not both')

        return m_in, g_in

    def get_excess_deposit(self, amount_m, amount_g):
        p = self.spot_price()
        allowed_deposit_value = min([p*amount_g/self.weights[1], amount_m/self.weights[0]])
        excess_m = amount_m - allowed_deposit_value/2
        excess_g = amount_g - allowed_deposit_value/2/p
        return excess_m, excess_g

    def deposit(self, amount_m, amount_g, swap=False):
        orig_value = self.total_value
        # User only gets credit for tokens supplied in correct ratio
        p = self.spot_price()
        if swap:
            # Swap to correct ratio
            excess_m, excess_g = self.get_excess_deposit(amount_m, amount_g)
            if excess_m > 0:
                swap_m, _ = self.get_swap_for_deposit(amount_m=excess_m)
                swap_tx = self.swap(self.money_name, swap_m, self.gov_name)
                print(swap_tx)
                amount_m -= swap_m
                amount_g += swap_tx.amount_out
            elif excess_g > 0:
                _, swap_g = self.get_swap_for_deposit(amount_g=excess_g)
                swap_tx = self.swap(self.gov_name, swap_g, self.money_name)
                print(swap_tx)
                amount_m += swap_tx.amount_out
                amount_g -= swap_g
        deposit_value = amount_m + p*amount_g
        allowed_deposit_value = min([p*amount_g/self.weights[1], amount_m/self.weights[0]])
        if isinstance(deposit_value, sp.Expr):
            if not deposit_value.equals(allowed_deposit_value):
                print(
                    f'Deposit not supplied in ratio {p}:1.  Value reduced from {deposit_value} to {allowed_deposit_value} ')
        else:
            if deposit_value != allowed_deposit_value:
                print(f'Deposit not supplied in ratio {p:0.2f}:1.  Value reduced from {deposit_value} to {allowed_deposit_value} ')
        r = self.weights[0]/self.weights[1]
        deposit_m = min([amount_m, r*p*amount_g])
        deposit_g = min([amount_m/p/r, amount_g])
        deposit_value = deposit_m + deposit_g*p
        self.tokens[0] += amount_m
        self.tokens[1] += amount_g
        lp_out = (deposit_value/orig_value)*self.lp_tokens
        self.lp_tokens += lp_out
        return lp_out

    def withdraw(self, lp_amount, tok_out=None):
        f = lp_amount/self.lp_tokens
        m_out = self.tokens[0]*f
        g_out = self.tokens[1]*f
        self.tokens[0] -= m_out
        self.tokens[1] -= g_out
        if tok_out is None:
            # Withdraw both tokens with zero slippage
            return m_out, g_out
        elif tok_out == self.money_name:
            # Withdraw money only, trading governance tokens back to pool
            swap = self.swap(self.gov_name, g_out)
            return m_out + swap.amount_out
        elif tok_out == self.gov_name:
            # Withdraw governance tokens only, trading money back to pool
            swap = self.swap(self.money_name, m_out)
            return g_out + swap.amount_out
        else:
            raise ValueError(f'Unknown token out {tok_out}')

    @property
    def total_value(self):
        return self.tokens[0]/self.weights[0]

    @property
    def invariant(self):
        return np.prod(np.array(self.tokens)**np.array(self.weights))

    def get_state(self):
        return self.total_value, self.tokens[0], self.tokens[1], self.spot_price()

    def __repr__(self):
        if self.weights is None:
            out_str = 'Uniswap Pool weights not set.'
        else:
            total_value, x_m, x_g, p = self.get_state()
            if isinstance(total_value, sp.Expr):
                out_str = f'Uniswap Pool Balance: {total_value}'
                out_str += f' = {x_m} {self.money_name}'
                out_str += f' + {x_g} {self.gov_name} @ price {p} (value {x_g*p})'
                out_str += f'  Invariant {self.invariant}'
            else:
                out_str = f'Uniswap Pool Balance: {total_value:0.2f}'
                out_str += f' = {x_m:0.2f} {self.money_name}'
                out_str += f' + {x_g:0.2f} {self.gov_name} @ {p:0.2f} ({x_g*p:0.2f})'
                out_str += f'  Invariant {self.invariant:0.2f}'
        return out_str


class CompoundAmm:
    def __init__(self, amm, pool):
        self.amm = amm    # Mettalex DEX
        self.pool = pool  # Uniswap
        self.total_gov_in = 0
        self.total_gov_out = 0
        self.swap_strategy = None

    @property
    def _token_map(self):
        return dict(
            zip(
                ['coin', 'long', 'short', 'money', 'gov'],
                self.amm.token_names + self.pool.token_names
            )
        )

    @property
    def token_names(self):
        return list(self._token_map.values())

    def name_lookup(self, tok):
        return self._token_map[tok]

    def swap(self, tok_in, amount, tok_out, report=False, convert=True):
        swap = self.amm.swap(tok_in, amount, tok_out, report=False)
        if tok_in == self.name_lookup('coin'):
            # Deposit money plus matching governance in pool
            gov_in = amount / self.pool.spot_price()
            self.total_gov_in += gov_in
            self.pool.deposit(amount, gov_in)

        if tok_out == self.name_lookup('coin'):
            gov_out = swap.amount_out / self.pool.spot_price()
            self.total_gov_out += gov_out
            print(f'{swap.amount_out:0.2f} {tok_out} out converted to {gov_out:0.2f} {self.name_lookup("gov")}')

            if report:
                print(swap)
                print(self)

            if convert:
                # Swap governance tokens for money in Uniswap pool
                swap_g = self.pool.swap(self.name_lookup('gov'), gov_out, self.name_lookup('money'), report=False)
                if report:
                    print(swap_g)
                    print(self.pool)
        else:
            if report:
                print(swap)
                print(self)

        return swap

    def swap_out(self, tok_in, amount, tok_out, report=False, convert=False):
        amount_in = self.amm.get_amount_in(tok_in, amount, tok_out)
        swap = self.swap(tok_in, amount_in, tok_out, report=report, convert=convert)
        return swap

    def reweight(self, price, report=False):
        self.amm.reweight(price, report=report)

    def __repr__(self):
        out_str = str(self.amm)
        out_str += '\n'
        out_str += str(self.pool)
        out_str += '\n'
        out_str += f'{self.name_lookup("gov")} in from LP: {self.total_gov_in:0.2f}  {self.name_lookup("gov")} out to Traders: {self.total_gov_out:0.2f}'
        return out_str


def default_simple_setup(coin=10000, ltk=1000, stk=1000, price=0.5, collateral=100, token_names=None):
    amm = AMM(tokens=[coin, ltk, stk], price=price, collateral=collateral, token_names=token_names)
    weights, swap_constraint = define_equations(*define_symbols())
    amm.set_weight_functions(weights)
    amm.set_swap_function(swap_constraint)
    amm.reweight()
    return amm


def default_compound_setup(
        coin=10000, ltk=1000, stk=1000, price=0.5, collateral=100,
        money=100000, governance=1_000_000, split_coin=False,
        amm_tokens=None, uniswap_tokens=None
):
    if split_coin:
        # Ignore long and short tokens instead split coin deposit 50:50 coin:long + short
        ltk = coin/2/collateral
        stk = coin/2/collateral
        coin = coin/2

    amm_tokens = amm_tokens or ['Chip', 'Long', 'Short']
    uniswap_tokens = uniswap_tokens or ['BUSD', 'MTLX']

    amm = default_simple_setup(coin, ltk, stk, price, collateral, token_names=amm_tokens)
    pool = UniswapPool([money, governance], token_names=uniswap_tokens)
    compound_amm = CompoundAmm(amm, pool)
    return compound_amm


def default_compund_setup_2():
    amm = default_compound_setup(
        coin=1_000_000, price=0.5, collateral=100, split_coin=True,
        money=1_000_000, governance=1_000_000)
    return amm


class Simulation:
    def __init__(self, amm=None, report=False):
        self.amm = amm
        self.report = report

    def buy(self, amount, tok_out):
        self.amm.swap_out(
            self.amm.name_lookup('coin'), amount=amount, tok_out=tok_out, report=self.report
        )

    def sell(self, amount, tok_in, convert=False):
        self.amm.swap(
            tok_in, amount=amount, tok_out=self.amm.name_lookup('coin'),
            report=self.report, convert=convert
        )


def simple_sim(amm=None):
    # Run a default simulation assuming coin used to open AMM positions is money
    if amm is None:
        amm = default_simple_setup(10000, 1000, 1000)
    print(amm)

    coin = amm.name_lookup('coin')
    ltk = amm.name_lookup('long')
    stk = amm.name_lookup('short')

    # swap_out = 'swap x coin for 100 short'
    print(f'\nFirst trade: buy 100 {stk}')
    _ = amm.swap_out(coin, 100, stk, report=True)
    print(f'\nSecond trade: buy 100 {stk}')
    _ = amm.swap_out(coin, 100, stk, report=True)
    print(f'\nThird trade: spend 5000 {coin} to buy {stk}')
    _ = amm.swap(coin, 5000, stk, report=True)
    print(f'\nFourth trade: buy 100 {ltk}')
    _ = amm.swap_out(coin, 100, ltk, report=True)
    print('\nChange underlying price to 0.1')
    amm.reweight(0.1, report=True)
    print(f'\nSell 100 {stk} back to AMM')
    amm.swap(stk, 100, coin, report=True)
    print(f'\nSell 100 {stk} back to AMM')
    amm.swap(stk, 100, coin, report=True)
    print(f'\nSell 77.6 {stk} back to AMM')
    amm.swap(stk, 77.59, coin, report=True)
    print('\nChange underlying price to 0.9')
    amm.reweight(0.9, report=True)
    print(f'\nSell 100 {ltk} back to AMM')
    amm.swap(ltk, 100, coin, report=True)


if __name__ == '__main__':
    simple_sim()
