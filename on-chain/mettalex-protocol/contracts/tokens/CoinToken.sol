pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CoinToken is ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    address public owner;
    mapping(address => bool) public whitelist;

    event Mint(address indexed _to, uint256 _value);
    event Burn(address indexed _to, uint256 _value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        _mint(msg.sender, 1560000000 * 10**18);
        whitelist[msg.sender] = true;
        owner = msg.sender;
    }

    function setWhitelist(address who, bool enable) public {
        require(msg.sender == owner, "OWNER_ONLY");
        whitelist[who] = enable;
    }

    function mint(address _to, uint256 _value) public {
        require(whitelist[msg.sender] == true, "WHITELISTED_ONLY");
        _mint(_to, _value);
        emit Mint(_to, _value);
    }

    function burn(address _from, uint256 _value) public {
        require(whitelist[msg.sender] == true, "WHITELISTED_ONLY");
        _burn(_from, _value);
        emit Burn(_from, _value);
    }
}
