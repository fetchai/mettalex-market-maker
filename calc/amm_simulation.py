import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from amm import default_simple_setup


def plot_trades(trade_index, long_swaps, short_swaps):
    cmap = sns.color_palette()
    plt.plot(trade_index, [s.trade_price for s in long_swaps], c=cmap[0], marker='.', label='Long')
    plt.plot(trade_index, [s.trade_price for s in short_swaps], c=cmap[1], marker='.', label='Short')
    plt.plot(trade_index, [s.fair_price for s in long_swaps],
             c=cmap[0], marker='.', linestyle='--', label='Fair Long', alpha=0.2)
    plt.plot(trade_index, [s.fair_price for s in short_swaps],
             c=cmap[1], marker='.', linestyle='--', label='Fair Short', alpha=0.2)
    plt.xlabel('Trade Index')
    plt.ylabel('Token Price')
    plt.legend()


class Simulator:
    def __init__(
            self, initial_liquidity=1_000_000, trade_volume=100_000, f_long=0.6, n_trades=10,
            v=0.5, C=100, coin_fraction=0.5
    ):
        self.initial_liquidity = initial_liquidity
        self.trade_volume = trade_volume
        self.f_long = f_long
        self.n_trades = n_trades
        self.v = v
        self.C = C
        self.coin_fraction = coin_fraction  # Fraction of initial liquidity used as coin
        self.amm = None

    def init_amm(self):
        self.amm = default_simple_setup(
            self.initial_liquidity * self.coin_fraction,
            self.initial_liquidity / self.C * (1 - self.coin_fraction),
            self.initial_liquidity / self.C * (1 - self.coin_fraction),
            self.v, self.C
        )

    def reset_amm(self, price=0.5, coin_fraction=None):
        if coin_fraction is not None:
            self.coin_fraction = coin_fraction
        self.amm.tokens = [
            self.initial_liquidity * self.coin_fraction,
            self.initial_liquidity / self.C * (1 - self.coin_fraction),
            self.initial_liquidity / self.C * (1 - self.coin_fraction),
        ]
        self.amm.cumulative_tokens = [0., 0., 0.]
        self.amm.price = price
        self.amm.reweight()

    def simulate_trades(
            self, price=0.5, trade_volume=None, f_long=None, n_trades=None,
            report=True, coin_fraction=None
    ):
        amm = self.amm or self.init_amm()
        self.reset_amm(price=price, coin_fraction=coin_fraction)
        trade_volume = trade_volume or self.trade_volume
        f_long = f_long or self.f_long
        n_trades = n_trades or self.n_trades
        trades_long = trade_volume * f_long
        trades_short = trade_volume * (1 - f_long)

        p_l = amm.spot_price('long')
        p_s = amm.spot_price('short')
        fair_long = trades_long / p_l
        fair_short = trades_short / p_s

        if report:
            print(amm)
            print(f'At fair value ${trades_long:0.2f} would purchase {fair_long:0.2f} long tokens')
            print(f'At fair value ${trades_short:0.2f} would purchase {fair_short:0.2f} short tokens')
            print('\n')
        long_swaps = []
        short_swaps = []
        # Keep track of total value and DEX invariant
        amm_total_value = [amm.total_value]
        amm_invariant = [amm.invariant]
        amm_safe_balance = [amm.safe_balance]
        amm_unsafe_balance = [amm.unsafe_balance]
        amm_liabilities = [amm.liabilities]

        trade_index = range(n_trades)
        for _ in trade_index:
            long_swaps.append(amm.swap('coin', trades_long / n_trades, 'long'))
            short_swaps.append(amm.swap('coin', trades_short / n_trades, 'short'))
            amm_total_value.append(amm.total_value)
            amm_invariant.append(amm.invariant)
            amm_safe_balance.append(amm.safe_balance)
            amm_unsafe_balance.append(amm.unsafe_balance)
            amm_liabilities.append(amm.liabilities)

        actual_long = sum([s.amount_out for s in long_swaps])
        actual_short = sum([s.amount_out for s in short_swaps])
        slippage_long = -((actual_long/fair_long) - 1)
        slippage_short = -((actual_short/fair_short) - 1)

        if report:
            print(amm)
            print(f'Actual purchase {actual_long:0.2f} long tokens ({slippage_long:0.2%} slippage)')
            print(f'Actual purchase {actual_short:0.2f} short tokens ({slippage_short:0.2%} slippage)')
            fig = plt.figure(figsize=(14, 6))
            plt.subplot(1, 3, 1)
            plot_trades(trade_index, long_swaps, short_swaps)
            plt.subplot(1, 3, 2)
            plt.plot(np.array(amm_total_value) - amm_total_value[0])
            plt.title('AMM Total Value - Initial Value')
            plt.subplot(1, 3, 3)
            plt.plot(amm_invariant)
            plt.title('Amm Invariant')
            fig.tight_layout()

        res = {
            'long_swaps': long_swaps,
            'short_swaps': short_swaps,
            'total value': amm_total_value,
            'invariant': amm_invariant,
            'safe': amm_safe_balance,
            'unsafe': amm_unsafe_balance,
            'liabilities': amm_liabilities
        }

        return res

    def lp_pnl_map(self, price=None, trade_volume=None, f_long=None, n_trades=None,
                   field='total value'):
        trade_volume = trade_volume or self.trade_volume
        n_trades = n_trades or self.n_trades
        f_long = f_long or self.f_long

        if price is None:
            price = (1. + np.arange(9)) / 10.0

        values = np.zeros((n_trades + 1, len(price)))
        for i in range(len(price)):
            res = self.simulate_trades(
                price=price[i], trade_volume=trade_volume, f_long=f_long, n_trades=n_trades,
                report=False
            )
            values[:, i] = res[field]

        # Initial AMM values
        self.reset_amm()

        if field == 'total value':
            # Plot percentage return
            values = np.round(values, -1) / self.amm.total_value - 1
            field_str = f'LP return on {self.amm.total_value:0.0f}'
            heatmap_args = dict(fmt="0.2%", center=0., cmap='bwr_r')
        elif field in {'safe', 'unsafe'}:
            values = values / self.amm.total_value
            field_str = f'{field.capitalize()} balance % of {self.amm.total_value:0.0f}'
            heatmap_args = dict(fmt="0.2%", cmap='bwr_r' if field == 'safe' else 'bwr')
        elif field in {'liabilities'}:
            field_str = f'{field.capitalize()} % of {self.amm.total_value:0.0f}'
            values = values / self.amm.total_value
            heatmap_args = dict(fmt="0.2%", cmap='bwr', center=0.5)
        else:
            raise ValueError(f'Unknown field: {field}')

        fig = plt.figure(figsize=(10, 8))
        df = pd.DataFrame(
            values,
            columns=price,
            index=trade_volume * np.arange(n_trades + 1) / n_trades,

        )
        df.index.name = 'total trade volume'
        df.columns.name = '$v$'
        _ = sns.heatmap(df, annot=True, linewidth=0.5, **heatmap_args)
        _ = plt.title(f'{field_str} for {f_long:0.0%} Long : {1 - f_long:0.0%} Short')
        return df