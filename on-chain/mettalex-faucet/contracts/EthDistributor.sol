pragma solidity ^0.5.11;

contract EthDistributor {
    address payable public admin;
    uint256 public dailyLimit;

    constructor(address payable _admin, uint256 _dailyLimit) public {
        admin = _admin;
        dailyLimit = _dailyLimit;
    }

    function() external payable {
        require(msg.sender == admin, "Invalid request");
    }

    function updateAdmin(address payable _admin) external {
        require(msg.sender == admin, "Only Admin!");
        admin = _admin;
    }

    function updateDailyLimit(uint256 _dailyLimit) external {
        require(msg.sender == admin, "Only Admin!");
        dailyLimit = _dailyLimit;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function sendEther(address payable user) public payable returns (bool) {
        require(msg.sender == admin, "Only Admin!");
        require(msg.value == dailyLimit, "Invalid Amount");
        user.transfer(msg.value);
        return true;
    }

    function withdraw() public {
        uint256 contractBalance = address(this).balance;
        admin.transfer(contractBalance);
    }
}
