pragma solidity ^0.5.0;
/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;
        return c;
    }
    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }
    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see `ERC20Detailed`.
 */
interface IUSDT {
    function balanceOf(address account) external view returns (uint256);
    function mint(address _to, uint256 _value) external;
}

contract USDTFaucet {
    using SafeMath for uint256;
    uint256 public dailyLimit;
    address public tokenAddress;
    address public owner;
    //mapping for amount withdrawn and timestamp of withdrawal
    mapping(address => uint256) public amountWithdrawn;
    mapping(address => uint256) public lastWithdrawnAt;

    constructor(address _tokenAddress, uint256 _limit) public {
        tokenAddress = _tokenAddress;
        dailyLimit = _limit;
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    function updateTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }
    
    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }
    
    function updateDailyLimit(uint256 _dailyLimit) external onlyOwner {
        dailyLimit = _dailyLimit;
    }

    function request(address user, uint256 amount) external onlyOwner {
        require(msg.sender == owner, "Only Owner!");
        require(amount <= dailyLimit, "Amount exceeding limit");
        if (now.sub(lastWithdrawnAt[user]) <= 86400) {
            require(
                amountWithdrawn[user].add(amount) <= dailyLimit,
                "Daily Limit Exceeded"
            );
        } else {
            amountWithdrawn[user] = 0;
            lastWithdrawnAt[user] = now;
        }
        IUSDT(tokenAddress).mint(user, amount);
        amountWithdrawn[user] = amountWithdrawn[user].add(amount);
    }
}
