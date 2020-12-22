# Mettalex Vault


## Position Tokens

The position tokens track the price change of an underlying asset (long tokens), or the negative of that change (short tokens).  Leverage is achieved by the token price being a fraction of the asset price.  This leverage enables hedgers to manage their risk exposure at minimal cost. 

## Mettalex vault

It contains the liquidity coming from the collateral used to back a pair of L and S Position tokens. 
It maintains the collateral ratio which is calculated based on the floor and cap prices of the commodity set with the deployment.
Vault contract maintains the spot price of each commodity which is maintained with the help of Oracle (which are scheduled to update price of commodity in vault contract)

If the commodity spot prices crosses floor or cap values, it is considered settled. In this case, user can still borrow the collateral deposited by burning the position tokens held.

## Certik Audit (December 12th, 2020) Note 

SEV-01: Duplicate SafeERC20 library (Vault.sol)

SafeERC20 library existing under vault is an structural clone of openzeppelin's SafeERC20 but has a modification in it's inteface.
Comparing with IERC20 interface there was a need for some methods to be added as functional requirement for the tokens which are :
1. mint(address _to, uint256 _value) external;
2. burn(address _from, uint256 _value) external;.
These mehods are added to the IToken interface which is imported in Vault's SafeERC20 library which thereafter utilizes the IToken over IERC20.
This is the key reason for having a seperate library instead of importing direct openzeppelin's SafeERC20.

# Test

Please refer to ../mettalex-protocol for test cases on mettalex-vault