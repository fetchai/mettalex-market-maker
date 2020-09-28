pragma solidity ^0.5.16;

import "./interfaces/Ibalancer.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMtlxVault.sol";
import "./interfaces/IYController.sol";
import "./lib/Address.sol";
import "./lib/SignedSafeMath.sol";
import "./lib/SafeMath.sol";
import "./lib/SafeERC20.sol";

interface IStrategy {
    function deposit() external;

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);

    /** Need to decide on Strategy API implementation for following methods */
    // function withdrawAll() external;
    // function withdraw(address) external;
}

contract StrategyBalancerMettalex is IStrategy {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    address public want; // = address(0xCfEB869F69431e42cdB54A4F4f105C19C080A601);
    address public governance;
    address public controller;
    bool public breaker; // = false;

    //to maintain Strategy for each commodity (commodity index -> address)
    address[] public strategyManager;

    address public depositTo;
    address public withdrawFrom;

    // Supply tracks the number of `want` that we have lent out of other distro's
    uint256 public supply; // = 0;

    // OpenZeppelin SDK upgradeable contract
    bool private initialized;

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setBreaker(bool _breaker) public {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    function initialize(address _controller, address _want) public {
        // General initializer
        require(!initialized, "Already initialized");
        want = _want;
        governance = msg.sender;
        controller = _controller;
        breaker = false;
        supply = 0;
        initialized = true;
    }

    function addStrategy(address _strategyAddress) public {
        require(msg.sender == governance, "!governance");
        strategyManager.push(_strategyAddress);
    }

    function removeStrategy(uint256 _index) public {
        require(msg.sender == governance, "!governance");
        uint256 length = strategyManager.length;
        delete strategyManager[_index];
        strategyManager[_index] = strategyManager[length - 1];
        delete strategyManager[length - 1];
        strategyManager.pop();
    }

    function updateStrategy(uint256 _index, address _strategyAddress) public {
        require(msg.sender == governance, "!governance");
        strategyManager[_index] = _strategyAddress;
    }

    function updateStrategyToUse(address _deposit, address _withdraw) public {
        require(msg.sender == governance, "!governance");
        depositTo = _deposit;
        withdrawFrom = _withdraw;
    }

    function deposit() external {
        require(breaker == false, "!breaker");
        require(msg.sender == controller, "!controller");
        require(depositTo != address(0), "ERR_DEPOSIT_STRATEGY");

        uint256 amount = IERC20(want).balanceOf(address(this));

        supply = supply.sub(amount);

        IERC20(want).safeTransfer(depositTo, amount);
        IStrategy(depositTo).deposit();
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(breaker == false, "!breaker");
        require(msg.sender == controller, "!controller");
        require(withdrawFrom != address(0), "ERR_WITHDRAW_STRATEGY");

        supply = supply.sub(_amount);
        IStrategy(withdrawFrom).withdraw(_amount);
    }

    function balanceOf() external view returns (uint256 totalBalance) {
        totalBalance = 0;

        for (uint256 index = 0; index < strategyManager.length; index++) {
            totalBalance = totalBalance.add(
                _getStrategyBalance(strategyManager[index])
            );
        }
    }

    function _getStrategyBalance(address _strategy)
        internal
        view
        returns (uint256 balance)
    {
        if (_strategy == address(0)) return 0;
        balance = IStrategy(_strategy).balanceOf();
    }
}
