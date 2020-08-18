/**
 *Submitted for verification at Etherscan.io on 2020-07-27
*/

pragma solidity ^0.5.16;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


interface Controller {
    function vaults(address) external view returns (address);
}

interface Balancer {
    function isPublicSwap() external view returns (bool);
    function isFinalized() external view returns (bool);
    function isBound(address t) external view returns (bool);
    function getNumTokens() external view returns (uint);
    function getCurrentTokens() external view returns (address[] memory tokens);
    function getFinalTokens() external view returns (address[] memory tokens);
    function getDenormalizedWeight(address token) external view returns (uint);
    function getTotalDenormalizedWeight() external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
    function getBalance(address token) external view returns (uint);
    function getSwapFee() external view returns (uint);
    function getController() external view returns (address);

    function setSwapFee(uint swapFee) external;
    function setController(address manager) external;
    function setPublicSwap(bool public_) external;
    function finalize() external;
    function bind(address token, uint balance, uint denorm) external;
    function rebind(address token, uint balance, uint denorm) external;
    function unbind(address token) external;
    function gulp(address token) external;

    function getSpotPrice(address tokenIn, address tokenOut) external view returns (uint spotPrice);
    function getSpotPriceSansFee(address tokenIn, address tokenOut) external view returns (uint spotPrice);

    function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    ) external pure returns (uint spotPrice);

    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    ) external pure returns (uint tokenAmountOut);
}

interface MettalexVault {
    function collateralPerUnit() external view returns (uint _collateralPerUnit);
    function collateralFeePerUnit() external view returns (uint _collateralFeePerUnit);
    function mintPositions(uint qtyToMint) external;
}

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

/*

 Strategy ~ 50% USDT to LTK + STK
 USDT + LTK + STK into balancer
 (No yield farming, just Balancer pool fees)

*/

contract StrategyBalancerMettalex {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // ganache --deterministic USDT
    address public want; // = address(0xCfEB869F69431e42cdB54A4F4f105C19C080A601);

    address public balancer; // = address(0x72Cd8f4504941Bf8c5a21d1Fd83A96499FD71d2C);

    address public mettalex_vault; // = address(0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb);
    address public long_token; // = address(0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B);
    address public short_token; // = address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);

    address public governance;
    address public controller;
    bool public breaker; // = false;
    // Supply tracks the number of `want` that we have lent out of other distro's
    uint public supply;  // = 0;

    // OpenZeppelin SDK upgradeable contract
    bool private initialized;

    function initialize(address _controller) public {
        require(!initialized, "Already initialized");
        want = address(0xCfEB869F69431e42cdB54A4F4f105C19C080A601);
        balancer = address(0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78);
        mettalex_vault = address(0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb);
        long_token = address(0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B);
        short_token = address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);
        governance = msg.sender;
        controller = _controller;
        breaker = false;
        supply = 0;
    }

//    constructor(address _controller) public {
//        governance = msg.sender;
//        controller = _controller;
//    }

    function setBreaker(bool _breaker) public {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    function deposit() external {
        require(breaker == false, "!breaker");
        // TODO: Unbind tokens from Balancer pool and redeem position tokens against vault
        // do this now

        // Get coin token balance and allocate half to minting position tokens
        uint _balance = IERC20(want).balanceOf(address(this));
        uint _want = _balance.div(2);
        IERC20(want).safeApprove(mettalex_vault, 0);
        IERC20(want).safeApprove(mettalex_vault, _want);

        MettalexVault mVault = MettalexVault(mettalex_vault);
        uint coinPerUnit = mVault.collateralPerUnit();
        uint feePerUnit = mVault.collateralFeePerUnit();
        uint totalPerUnit = coinPerUnit.add(feePerUnit);
        uint qtyToMint = _want.div(totalPerUnit);

        uint _before = _balance;
        mVault.mintPositions(qtyToMint);

        // Approve transfer Balancer balancer pool
        IERC20(want).safeApprove(balancer, 0);
        IERC20(want).safeApprove(balancer, 9571250000000000000000);
        IERC20(long_token).safeApprove(balancer, 0);
        IERC20(long_token).safeApprove(balancer, 95000000);
        IERC20(short_token).safeApprove(balancer, 0);
        IERC20(short_token).safeApprove(balancer, 95000000);

        // Then supply minted tokens and remaining collateral to Balancer pool
        Balancer bPool = Balancer(balancer);
        bPool.bind(want, 9571250000000000000000, 25000000000000000000);
        bPool.bind(long_token, 95000000, 12500000000000000000);
        bPool.bind(short_token, 95000000, 12500000000000000000);


//        uint _after = IERC20(want).balanceOf(address(this));
//        supply = supply.add(_before.sub(_after));
//
//        uint _long = IERC20(long_token).balanceOf(address(this));
//        uint _short = IERC20(short_token).balanceOf(address(this));

//        uint _total = IERC20(balancer).totalSupply();
//        uint _balancerMUSD = IERC20(mUSD).balanceOf(balancer);
//        uint _poolAmountMUSD = _musd.mul(_total).div(_balancerMUSD);
//
//        uint _balancerUSDC = IERC20(want).balanceOf(balancer);
//        uint _poolAmountUSDC = _want.mul(_total).div(_balancerUSDC);
//
//        uint _poolAmountOut = _poolAmountMUSD;
//        if (_poolAmountUSDC < _poolAmountOut) {
//            _poolAmountOut = _poolAmountUSDC;
//        }
//
//        IERC20(want).safeApprove(balancer, 0);
//        IERC20(want).safeApprove(balancer, _want);
//        IERC20(mUSD).safeApprove(balancer, 0);
//        IERC20(mUSD).safeApprove(balancer, _musd);
//
//        uint[] memory _maxAmountIn = new uint[](2);
//        _maxAmountIn[0] = _musd;
//        _maxAmountIn[1] = _want;
//        _before = IERC20(want).balanceOf(address(this));
//        Balancer(balancer).joinPool(_poolAmountOut, _maxAmountIn);
//        _after = IERC20(want).balanceOf(address(this));
//        supply = supply.add(_before.sub(_after));
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(address(_asset) != want, "!c");
        require(address(_asset) != balancer, "!c");
        require(address(_asset) != mettalex_vault, "!c");
        require(address(_asset) != long_token, "!c");
        require(address(_asset) != short_token, "!c");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    function withdrawM(uint _amount) internal returns (uint) {
        if (_amount > supply) {
            // Pool made too much profit, so we reset to 0 to avoid revert
            supply = 0;
        } else {
            supply = supply.sub(_amount);
        }

        uint _before = IERC20(want).balanceOf(address(this));
//        MStable(mUSD).redeem(want, _amount);
        uint _after  = IERC20(want).balanceOf(address(this));
        return _after.sub(_before);
    }

    function withdrawBPT(uint _amount) internal returns (uint) {
        uint _calc = calculateRatio(_amount);
        _amount = _amount.sub(_amount.mul(5).div(10000));
        return _withdrawSome(_calc, _amount);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
//        uint _balance = IERC20(want).balanceOf(address(this));
//        if (_balance < _amount) {
//            uint _musd = normalize(IERC20(mUSD).balanceOf(address(this)));
//            uint _remainder = _amount.sub(_balance);
//            if (_musd > 0) {
//                if (_musd > _remainder) {
//                    _amount = withdrawM(_remainder);
//                    _amount = _amount.add(_balance);
//                } else {
//                    _remainder = _remainder.sub(_musd);
//                    uint _withdrew = withdrawM(_musd);
//                    _amount = _withdrew.add(_balance);
//                    _withdrew = withdrawBPT(_remainder);
//                    _amount = _amount.add(_withdrew);
//                }
//            } else {
//                _amount = withdrawBPT(_remainder);
//                _amount = _amount.add(_balance);
//            }
//
//        }
//
//
//        address _vault = Controller(controller).vaults(want);
//        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
//        IERC20(want).safeTransfer(_vault, _amount);

    }

    function redeem() external {
        require(msg.sender == governance, "!governance");
//        uint _balance = normalize(IERC20(mUSD).balanceOf(address(this)));
//        if (_balance > supply) {
//            // Pool made too much profit, so we reset to 0 to avoid revert
//            supply = 0;
//        } else {
//            supply = supply.sub(_balance);
//        }
//
//        MStable(mUSD).redeem(want, _balance);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));

        address _vault = Controller(controller).vaults(want);
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);

    }

    function _withdrawAll() internal {
        uint _bpt = IERC20(balancer).balanceOf(address(this));
//        uint[] memory _minAmountOut = new uint[](2);
//        _minAmountOut[0] = 0;
//        _minAmountOut[1] = 0;
//        uint _before = IERC20(want).balanceOf(address(this));
//        Balancer(balancer).exitPool(_bpt, _minAmountOut);
//        uint _after = IERC20(want).balanceOf(address(this));
//        uint _diff = _after.sub(_before);
//        if (_diff > supply) {
//            // Pool made too much profit, so we reset to 0 to avoid revert
//            supply = 0;
//        } else {
//            supply = supply.sub(_after.sub(_before));
//        }
//        uint _musd = IERC20(mUSD).balanceOf(address(this));
//
//        // This one is the exception because it assumes we can redeem 1 USDC
//        _diff = normalize(_musd);
//        if (_diff > supply) {
//            // Pool made too much profit, so we reset to 0 to avoid revert
//            supply = 0;
//        } else {
//            supply = supply.sub(_diff);
//        }
//        MStable(mUSD).redeem(want, _diff);
    }

    function calculateRatio(uint _amount) public view returns (uint) {
        uint _want = IERC20(want).balanceOf(balancer);
//        uint _musd = normalize(IERC20(mUSD).balanceOf(balancer));
//        uint _total = _musd.add(_want);
//        uint _ratio = _amount.mul(_want).div(_total);
        return _want; // _ratio;
    }

    function _withdrawSome(uint256 _amount, uint _max) internal returns (uint) {
        uint _redeem = IERC20(balancer).totalSupply().mul(_amount).div(IERC20(want).balanceOf(balancer));
//        if (_redeem > IERC20(balancer).balanceOf(address(this))) {
//            _redeem = IERC20(balancer).balanceOf(address(this));
//        }
//        uint[] memory _minAmountOut = new uint[](2);
//        _minAmountOut[0] = 0;
//        _minAmountOut[1] = 0;
//
//        uint _before = IERC20(want).balanceOf(address(this));
//        uint _mBefore = IERC20(mUSD).balanceOf(address(this));
//        Balancer(balancer).exitPool(_redeem, _minAmountOut);
//        uint _mAfter = IERC20(mUSD).balanceOf(address(this));
//        uint _after = IERC20(want).balanceOf(address(this));
//
//        uint _musd = _mAfter.sub(_mBefore);
//        uint _withdrew = _after.sub(_before);
//
//        if (_withdrew > supply) {
//            // Pool made too much profit, so we reset to 0 to avoid revert
//            supply = 0;
//        } else {
//            supply = supply.sub(_withdrew);
//        }
//        _musd = normalize(_musd);
//        if (_musd > supply) {
//            // Pool made too much profit, so we reset to 0 to avoid revert
//            supply = 0;
//        } else {
//            supply = supply.sub(_musd);
//        }
//        _before = IERC20(want).balanceOf(address(this));
//        MStable(mUSD).redeem(want, _musd);
//        _after = IERC20(want).balanceOf(address(this));
//        _withdrew = _withdrew.add(_after.sub(_before));
//        if (_withdrew > _max) {
//            _withdrew = _max;
//        }
        return _redeem; //_withdrew;
    }

    function normalize(uint _amount) public view returns (uint) {
        return 1; // _amount.mul(10**IERC20(want).decimals()).div(10**IERC20(mUSD).decimals());
    }

    function balanceOf() public view returns (uint) {
        return IERC20(want).balanceOf(address(this))
                .add(supply);
    }


    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}