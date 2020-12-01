pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./IUSDT.sol";

contract USDTFaucetV2 {
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

    function getAmountWithdrawn(address _user)
        external
        view
        returns (uint256 amount)
    {
        if (amountWithdrawn[_user] == 0) return 0;
        amount = amountWithdrawn[_user];
    }

    function getLastWithdrawnAt(address _user)
        external
        view
        returns (uint256 time)
    {
        if (lastWithdrawnAt[_user] == 0) return 0;
        time = lastWithdrawnAt[_user];
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
