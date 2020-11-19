pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

/**
 * @title PositionToken
 */
contract PositionToken is ERC20Pausable, Ownable {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    bool public settled = false;
    uint256 public version;

    mapping(address => bool) public whitelist;

    event Mint(address indexed _to, uint256 _value);
    event Burn(address indexed _to, uint256 _value);

    /**
     * @dev The PositionToken constructor sets initial values.
     * @param _name string The name of the Position Token.
     * @param _symbol string The symbol of the Position Token.
     * @param _decimals uint8 The decimal value of Position Token.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _version
    ) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        version = _version;
        whitelist[msg.sender] = true;
    }

    /**
     * @dev Throws if called by any account other than Whitelisted users.
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender] == true, "WHITELISTED_ONLY");
        _;
    }

    /**
     * @dev Throws if the contract is settled
     */
    modifier notSettled() {
        require(!settled, "ALREADY_SETTLED");
        _;
    }

    /**
     * @dev Changes the whitelist status of a user.
     * @param who address The address of user whose whitelisted value is to be modified.
     * @param enable bool The boolean value indicating whether user is whitelisted.
     */
    function setWhitelist(address who, bool enable) public onlyOwner {
        whitelist[who] = enable;
    }

    /**
     * @dev Changes the whitelist status of a user.
     */
    function updateNameToSettled() public onlyOwner notSettled {
        settled = true;
        name = string(abi.encodePacked(name, " (settled)"));
    }

    /**
     * @dev Mints position tokens for a user.
     * @param _to address The address of beneficiary.
     * @param _value uint256 The amount of tokens to be minted.
     */
    function mint(address _to, uint256 _value)
        public
        notSettled
        onlyWhitelisted
        whenNotPaused
    {
        _mint(_to, _value);
        emit Mint(_to, _value);
    }

    /**
     * @dev Burns position tokens of a user.
     * @param _from address The address of beneficent.
     * @param _value uint256 The amount of tokens to be burned.
     */
    function burn(address _from, uint256 _value)
        public
        onlyWhitelisted
        whenNotPaused
    {
        _burn(_from, _value);
        emit Burn(_from, _value);
    }
}
