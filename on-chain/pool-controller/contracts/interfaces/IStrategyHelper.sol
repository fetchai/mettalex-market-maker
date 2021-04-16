pragma solidity ^0.5.16;

interface IStrategyHelper {
    function CalcDenormWeights(uint256[3] calldata bal, uint256 spotPrice, address mettalexVault) external view returns (uint256[3] memory wt);
}
