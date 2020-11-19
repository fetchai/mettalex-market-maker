pragma solidity ^0.5.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see `ERC20Detailed`.
 */
interface IUSDT {
    function balanceOf(address account) external view returns (uint256);

    function mint(address _to, uint256 _value) external;
}
