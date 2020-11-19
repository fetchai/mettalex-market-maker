pragma solidity ^0.5.16;

interface IYController {
    function vaults(address) external view returns (address);
}
