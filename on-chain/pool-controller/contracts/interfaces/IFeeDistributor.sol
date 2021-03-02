pragma solidity ^0.5.16;

interface IFeeDistributor {
    function sendFees(uint256 amount) external returns (bool);
}
