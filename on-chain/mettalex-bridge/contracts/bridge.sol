pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./IUSDT.sol";

contract Bridge {
    using SafeMath for uint256;
    uint256 public multiplier;
    uint256 public maxDeposit;
    address public owner;
    address public tokenAddress;
    address public USDTaddress;
    uint256 public depositLimit;
    mapping(address => uint256) public amountDeposited;


    constructor(address _USDTaddress, address _tokenAddress, uint256 _multiplier, uint256 _maxDeposit, uint256 _depositLimit) public {
        tokenAddress = _tokenAddress;
        USDTaddress = _USDTaddress;
        multiplier = _multiplier;
        maxDeposit = _maxDeposit;
        depositLimit = _depositLimit;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function setMultiplier(uint256 _multiplier)
        external
        onlyOwner
    {
        require(_multiplier > 0, "Multiplier should be greater than 0");
        multiplier = _multiplier;
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

    function setDepositLimit(uint256 _limit) external onlyOwner {
        depositLimit = _limit;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function deposit(uint256 _amountUSDT) external {
        require(_amountUSDT > multiplier, "ERR: min deposit");
        require(_amountUSDT <= maxDeposit, "ERR: max deposit");
        require(amountDeposited[msg.sender].add(_amountUSDT) < maxDeposit.mul(depositLimit), "ERR: deposit limit reached");
        IUSDT(USDTaddress).transferFrom(msg.sender, address(this), _amountUSDT);
        amountDeposited[msg.sender] = amountDeposited[msg.sender].add(_amountUSDT);
        IUSDT(tokenAddress).transfer(msg.sender, _amountUSDT.mul(multiplier));
    }

    function withdraw(uint256 _amountwUSDT) external {
        require(_amountwUSDT < IUSDT(USDTaddress).balanceOf(address(this)), "ERR: max Withdraw");
        uint256 amountOut = _amountwUSDT.div(multiplier);
        uint256 amountDecrease = amountOut.mul(multiplier);
        IUSDT(tokenAddress).transferFrom(msg.sender, address(this), amountDecrease);
        amountDeposited[msg.sender] = amountDeposited[msg.sender].sub(amountDecrease);
        IUSDT(USDTaddress).transfer(msg.sender, amountOut);
    }
    
}
