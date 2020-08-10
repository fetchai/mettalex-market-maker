pragma solidity ^0.5.2;

contract ERC20Basic {
    uint256 public totalSupply = 0;

    function transfer(address to, uint256 value) public returns (bool);

    function balanceOf(address who) public view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract BasicToken is ERC20Basic {
    using SafeMath for uint256;

    mapping(address => uint256) internal balances;

    /**
     * @dev transfer token for a specified address
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value) public returns (bool) {
        require(_to != address(0), "INVALID_ADDRESS");
        require(_value <= balances[msg.sender], "INSUFFICIENT_FUNDS");

        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to] + _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _owner The address to query the the balance of.
     * @return An uint256 representing the amount owned by the passed address.
     */
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public returns (bool);

    function approve(address spender, uint256 value) public returns (bool);

    function allowance(address owner, address spender)
        public
        view
        returns (uint256);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, BasicToken {
    mapping(address => mapping(address => uint256)) internal allowed;

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public returns (bool) {
        require(_to != address(0), "Invalid address");
        require(_value <= balances[_from], "Insufficient balance");
        require(
            _value <= allowed[_from][msg.sender],
            "Insufficienct allowance"
        );

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     *
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(address _spender, uint256 _addedValue)
        public
        returns (bool)
    {
        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(
            _addedValue
        );
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(address _spender, uint256 _subtractedValue)
        public
        returns (bool)
    {
        uint256 oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(address _owner, address _spender)
        public
        view
        returns (uint256)
    {
        return allowed[_owner][_spender];
    }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;

    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER_ONLY");
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(owner);
        owner = address(0);
    }
}

/**
 * @title PositionToken
 */
contract PositionToken is StandardToken, Ownable {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    bool public paused = false;
    bool public settled = false;
    uint8 public version;

    mapping(address => bool) public whitelist;

    event Mint(address indexed _to, uint256 _value);
    event Burn(address indexed _to, uint256 _value);
    event PauseNonWhitelisted();
    event UnpauseNonWhitelisted();

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
        uint8 _version
    ) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        version = _version;
        balances[msg.sender] = totalSupply;
        whitelist[msg.sender] = true;
        paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when contract is not paused for
     * non-whitelisted users.
     */
    modifier whenNotPausedForNonWhitelisted() {
        require(
            !paused || whitelist[msg.sender],
            "Paused for non-whitelisted users"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "Not paused for users");
        _;
    }

    /**
     * @dev Throws if called by any account other than Whitelisted users.
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender] == true, "WHITELISTED_ONLY");
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
     * @dev Mints position tokens for a user.
     * @param _to address The address of beneficiary.
     * @param _value uint256 The amount of tokens to be minted.
     */
    function mint(address _to, uint256 _value)
        public
        onlyWhitelisted
        whenNotPausedForNonWhitelisted
    {
        balances[_to] = balances[_to].add(_value);
        totalSupply = totalSupply.add(_value);
        emit Mint(_to, _value);
    }

    /**
     * @dev Burns position tokens of a user.
     * @param _from address The address of beneficent.
     * @param _value uint256 The amount of tokens to be burned.
     */
    function burn(address _from, uint256 _value) public onlyWhitelisted {
        balances[_from] = balances[_from].sub(_value);
        totalSupply = totalSupply.sub(_value);
        emit Burn(_from, _value);
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pauseNonWhitelisted()
        public
        onlyOwner
        whenNotPausedForNonWhitelisted
    {
        paused = true;
        emit PauseNonWhitelisted();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpauseNonWhitelisted() public onlyOwner whenPaused {
        paused = false;
        emit UnpauseNonWhitelisted();
    }

    /**
     * @dev Function to transfer tokens from sender.
     * @param _to address The address of the beneficiary.
     * @param _value uint256 The amount of tokens to be tranferred.
     * @return A bool specifying completion of transfer.
     */
    function transfer(address _to, uint256 _value)
        public
        whenNotPausedForNonWhitelisted
        returns (bool)
    {
        return super.transfer(_to, _value);
    }

    /**
     * @dev Function to transfer tokens from a particular account.
     * @param _from address The address of the beneficent.
     * @param _to address The address of the beneficiary.
     * @param _value uint256 The amount of tokens to be tranferred.
     * @return A bool specifying completion of transfer.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public whenNotPausedForNonWhitelisted returns (bool) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf
     * of msg.sender.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value)
        public
        whenNotPausedForNonWhitelisted
        returns (bool)
    {
        return super.approve(_spender, _value);
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(address _spender, uint256 _addedValue)
        public
        whenNotPausedForNonWhitelisted
        returns (bool success)
    {
        return super.increaseApproval(_spender, _addedValue);
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(address _spender, uint256 _subtractedValue)
        public
        whenNotPausedForNonWhitelisted
        returns (bool success)
    {
        return super.decreaseApproval(_spender, _subtractedValue);
    }
}
