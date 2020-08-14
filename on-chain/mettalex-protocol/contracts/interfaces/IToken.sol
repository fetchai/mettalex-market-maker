pragma solidity ^0.5.2;

contract IToken {
    function balanceOf(address account) external view returns (uint256);

    function mint(address _to, uint256 _value) external;

    function burn(address _from, uint256 _value) external;

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}
