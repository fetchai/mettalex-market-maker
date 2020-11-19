pragma solidity ^0.5.2;

interface IToken {
    function balanceOf(address account) external view returns (uint256);

    function allowance(address _from, address _to)
        external
        view
        returns (uint256);

    function mint(address _to, uint256 _value) external;

    function burn(address _from, uint256 _value) external;

    function approve(address _to, uint256 amount) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}
