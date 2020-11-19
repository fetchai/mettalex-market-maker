# Mettalex Vault


## Position Tokens

The position tokens track the price change of an underlying asset (long tokens), or the negative of that change (short tokens).  Leverage is achieved by the token price being a fraction of the asset price.  This leverage enables hedgers to manage their risk exposure at minimal cost. 

## Mettalex vault

It contains the liquidity coming from the collateral used to back a pair of L and S Position tokens. 
It maintains the collateral ratio which is calculated based on the floor and cap prices of the commodity set with the deployment.
Vault contract maintains the spot price of each commodity which is maintained with the help of Oracle (which are scheduled to update price of commodity in vault contract)

If the commodity spot prices crosses floor or cap values, it is considered settled. In this case, user can still borrow the collateral deposited by burning the position tokens held.