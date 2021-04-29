pragma solidity ^0.5.0;

// import "./SafeMath.sol";

import "./IYVault.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract RewardWrapper {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    address public owner;
    address public MTLXTokenAddress;
    address public collatearalAddress;
    address public yVault;

    struct depositInfo{
        uint256 blockNumber;
        uint256 amount;
    }

    struct UserInfo{
        depositInfo[] deposit;
        uint256 totalDeposit;
    }
    struct PoolInfo{
        uint256 amountAccumulated;
        uint256 rewardPerblock; //amount of MTLX reward per block
        uint256 initBlock;
    }

    mapping(address => UserInfo) public UserInformation;
    PoolInfo pool;

    constructor(address _MTLXAddress, address _collateral, address _yVault, uint256 _reward) public {
        MTLXTokenAddress = _MTLXAddress;
        collatearalAddress = _collateral;
        yVault = _yVault;
        owner = msg.sender;
        pool.amountAccumulated = 0;
        pool.initBlock = block.number;
        pool.rewardPerblock = _reward;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function setMTLXAddress(address _MTLXAddress) external onlyOwner{
        require(_MTLXAddress != address(0), "invalid address");
        MTLXTokenAddress = _MTLXAddress;
    }

    function deposit(uint256 _amount) external {
        //transferfrom user to yvault _amount
        
        IYVault(yVault).deposit(_amount);
        //transfer shares recieved to msg.sender here

        //update state
        pool.amountAccumulated.add(_amount);
        depositInfo memory newDeposit;
        newDeposit.blockNumber = block.number;
        newDeposit.amount = _amount;
        UserInformation[msg.sender].deposit.push(newDeposit);
        UserInformation[msg.sender].totalDeposit.add(_amount);
    }

    function totalRewards(address _user) public view returns (uint256){
        depositInfo[] memory depositArr = UserInformation[_user].deposit;
        uint256 netReward = 0;
        for(uint i = 0; i < depositArr.length; i++){
            uint256 reward = calculateReward(depositArr[i].blockNumber, depositArr[i].amount);
            netReward.add(reward);
        }
        return netReward;
    }

    //rewards = (amount/total pool amount)*(reward per block * (current block - initial block))
    function calculateReward(uint256 _blockNum, uint256 _amount) public view returns (uint256){
        uint256 numBlocks = block.number.sub(_blockNum);
        uint256 reward = _amount.mul(numBlocks).mul(pool.rewardPerblock);
        reward = reward.div(pool.amountAccumulated);
        return reward;
    }


    function withdraw(uint256 _amount) external returns (uint256) {
        IYVault(yVault).withdraw(_amount);
        //transfer _amount to msg.sender here
        
        //remove proportionately from each deposit
        UserInfo storage user = UserInformation[msg.sender];
        uint256 netReward = 0;
        depositInfo[] storage depositArr = user.deposit;

        for(uint i = 0; i < depositArr.length; i++){
            uint256 reward = calculateReward(depositArr[i].blockNumber, depositArr[i].amount);
            reward = reward.mul(_amount).div(user.totalDeposit);
            netReward.add(reward);
            depositArr[i].amount = depositArr[i].amount.mul(_amount).div(user.totalDeposit);
        }

        UserInformation[msg.sender].deposit = depositArr;
        
        //transfer netReward to user
        
        return netReward;
    }
    
}
