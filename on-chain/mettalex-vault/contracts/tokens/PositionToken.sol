// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.6.2;

import "OpenZeppelin/openzeppelin-contracts@3.0.0/contracts/access/AccessControl.sol";
import "OpenZeppelin/openzeppelin-contracts@3.0.0/contracts/token/ERC20/ERC20Pausable.sol";
import "OpenZeppelin/openzeppelin-contracts@3.0.0/contracts/token/ERC20/ERC20Burnable.sol";

/**
 * @dev {ERC20} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 */
contract PositionToken is Context, AccessControl, ERC20, ERC20Pausable {
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bool public settled = false;
    uint256 public version; 
    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */
    constructor(string memory name, 
                string memory symbol, 
                uint256 _version) public ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(WHITELIST_ROLE, _msgSender());
        version = _version; 
    }


    /**
     * @dev Throws if the contract is settled
     */
    modifier notSettled() {
        require(!settled, "ALREADY_SETTLED");
        _;
    }

   /**
     * @dev Throws if called by any account other than Whitelisted users.
     */
    modifier onlyWhitelisted() {
        require(hasRole(WHITELIST_ROLE, _msgSender()), "signer must be on whitelist");
        _;
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
 
   function mint(address to, uint256 amount) public virtual notSettled onlyWhitelisted {
        _mint(to, amount);
    }


    function burn(uint256 amount) external notSettled onlyWhitelisted{
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) external notSettled onlyWhitelisted {
        uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "ERC20: burn amount exceeds allowance");

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual onlyWhitelisted {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual onlyWhitelisted {
        require(hasRole(WHITELIST_ROLE, _msgSender()), "signer must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override (ERC20, ERC20Pausable) {
        super._beforeTokenTransfer(from, to, amount);
    }
}