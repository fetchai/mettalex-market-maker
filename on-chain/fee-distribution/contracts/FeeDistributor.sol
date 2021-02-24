pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract FeeDistributor is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public want;
    address public strategy;

    struct Distribution {
        uint256 totalFees;
        mapping (address => uint256) fractions;
        mapping (address => uint256) fundsWithdrawn;
        address[] users;
    }

    mapping (uint256 => Distribution) private distributions;
    mapping (address => uint256) private currentWithdrawalDistributionId;
    uint256 public distributionIndex;

    constructor (
        address _want,
        address _strategy,
        address[] memory userAddresses,
        uint256[] memory fractions
    ) public {
        require (_want != address(0));
        require (_strategy != address(0));

        want = _want;
        strategy = _strategy;

        uint256 fractionsLength = fractions.length;
        require (userAddresses.length == fractionsLength, "Error: Length mismatch");

        distributionIndex = 0;
        distributions[distributionIndex].users = userAddresses;
        for (uint256 i = 0; i < fractionsLength; i++) {
            distributions[distributionIndex].fractions[userAddresses[i]] = fractions[i];
        }
    }

    function updateFractions(
        address[] calldata userAddresses,
        uint256[] calldata fractions
    ) external onlyOwner returns (bool) {
        uint256 fractionsLength = fractions.length;
        require (userAddresses.length == fractionsLength);

        distributionIndex = distributionIndex.add(1);
        distributions[distributionIndex].users = userAddresses;
        for (uint256 i = 0; i < fractionsLength; i++) {
            distributions[distributionIndex].fractions[userAddresses[i]] = fractions[i];
        }
    }

    function sendFees(uint256 amount) external returns (bool) {
        require(amount > 0, "Invalid amount");
        require(msg.sender == strategy, "!strategy");

        IERC20(want).safeTransferFrom(msg.sender, address(this), amount);
        distributions[distributionIndex].totalFees = distributions[distributionIndex].totalFees.add(amount);

        return true;
    }

    function withdraw() external returns (bool) {
        uint256 totalAmount = 0;
        uint256 currentUserDistId = currentWithdrawalDistributionId[msg.sender];

        for(uint256 i = currentUserDistId; i <= distributionIndex; i++) {
            uint256 amount = getBalanceByDistribution(msg.sender, i);

            if (amount > 0) {
                distributions[i].fundsWithdrawn[msg.sender] = distributions[i].fundsWithdrawn[msg.sender].add(amount);
                totalAmount = totalAmount.add(amount);
            }
        }

        IERC20(want).safeTransfer(msg.sender, totalAmount);
        currentWithdrawalDistributionId[msg.sender] = distributionIndex;
        
        return true;
    }

    function updateStrategy(address _newStrategy) external onlyOwner returns (bool) {
        require (_newStrategy != address(0) && _newStrategy != strategy);
        strategy = _newStrategy;
    }

    function updateWant(address _newWant) external onlyOwner returns (bool) {
        require (_newWant != address(0) && _newWant != want);
        want = _newWant;
    }

    function getBalanceByDistribution(address user, uint256 distributionId) public view returns (uint256) {
        return distributions[distributionId].fractions[user].mul(distributions[distributionId].totalFees).div(100).sub(distributions[distributionId].fundsWithdrawn[user]);
    }

    function getBalance(address user) external view returns (uint256) {
        uint256 totalAmount = 0;
        for(uint256 i = 0; i <= distributionIndex; i++) {
            uint256 amount = getBalanceByDistribution(user, i);

            if (amount > 0) {
                totalAmount = totalAmount.add(amount);
            }
        }
        return totalAmount;
    }

    function getTotalFees(uint256 _distributionIndex) external view returns (uint256) {
        return distributions[_distributionIndex].totalFees;
    }

    function getUserAddresses(uint256 _distributionIndex) external view returns (address[] memory) {
        return distributions[_distributionIndex].users;
    }

    function getUserFraction(
        uint256 _distributionIndex, 
        address userAddress
    ) external view returns (uint256) {
        return distributions[_distributionIndex].fractions[userAddress];
    }
}