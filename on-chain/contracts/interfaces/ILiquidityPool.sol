pragma solidity ^0.5.16;

interface ILiquidityPool {
    function rebalance(uint target) returns (uint traded);
}
