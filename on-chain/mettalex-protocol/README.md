## Mettalex-Protocol

Mettalex-Protocol create positional tokens i.e long and short tokens for vault/commodity deployed.

## Test

> npm install

> npm run compile

> ganache-cli (run in a seperate terminal)

> npm run test

## Certik Audit (December 12th, 2020) Note 

SEV-01: Duplicate SafeERC20 library (Vault.sol)

SafeERC20 library existing under vault is an structural clone of openzeppelin's SafeERC20 but has a modification in it's inteface.
Comparing with IERC20 interface there was a need for some methods to be added as functional requirement for the tokens which are :
1. mint(address _to, uint256 _value) external;
2. burn(address _from, uint256 _value) external;.
These mehods are added to the IToken interface which is imported in Vault's SafeERC20 library which thereafter utilizes the IToken over IERC20.
This is the key reason for having a seperate library instead of importing direct openzeppelin's SafeERC20.