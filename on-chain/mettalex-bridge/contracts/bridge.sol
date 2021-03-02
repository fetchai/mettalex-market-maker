pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./IUSDT.sol";

contract Bridge {
    using SafeMath for uint256;
    uint256 public conversionRate;
    uint256 public maxDeposit;
    address public owner;
    address public tokenAddress;
    address public USDTaddress;
    uint256 public depositLimitMultiplier;
    mapping(address => uint256) public amountDeposited;


    constructor(address _USDTaddress, address _tokenAddress, uint256 _conversionRate, uint256 _maxDeposit, uint256 _depositLimitMultiplier) public {
        tokenAddress = _tokenAddress;
        USDTaddress = _USDTaddress;
        conversionRate = _conversionRate;
        maxDeposit = _maxDeposit;
        depositLimitMultiplier = _depositLimitMultiplier;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function setConversionRate(uint256 _conversionRate)
        external
        onlyOwner
    {
        require(_conversionRate > 0, "Multiplier should be greater than 0");
        conversionRate = _conversionRate;
    }

    function setMaxDeposit(uint256 _maxDeposit)
        external
        onlyOwner
    {
        maxDeposit = _maxDeposit;
    }

    function updateTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }

    function setdepositLimitMultiplier(uint256 _limit) external onlyOwner {
        depositLimitMultiplier = _limit;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function deposit(uint256 _amountUSDT) external {
        require(_amountUSDT > conversionRate, "ERR: min deposit");
        require(_amountUSDT <= maxDeposit, "ERR: max deposit");
        require(amountDeposited[msg.sender].add(_amountUSDT) < maxDeposit.mul(depositLimitMultiplier), "ERR: deposit limit reached");
        IUSDT(USDTaddress).transferFrom(msg.sender, address(this), _amountUSDT);
        amountDeposited[msg.sender] = amountDeposited[msg.sender].add(_amountUSDT);
        IUSDT(tokenAddress).transfer(msg.sender, _amountUSDT.mul(conversionRate));
    }

    function withdraw(uint256 _amountwUSDT) external {
        require(_amountwUSDT < IUSDT(USDTaddress).balanceOf(address(this)), "ERR: max Withdraw");
        uint256 amountOut = _amountwUSDT.div(conversionRate);
        uint256 amountDecrease = amountOut.mul(conversionRate);
        IUSDT(tokenAddress).transferFrom(msg.sender, address(this), amountDecrease);
        amountDeposited[msg.sender] = amountDeposited[msg.sender].sub(amountDecrease);
        IUSDT(USDTaddress).transfer(msg.sender, amountOut);
    }
    
}
