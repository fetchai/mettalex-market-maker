/**
 *Submitted for verification at Etherscan.io on 2020-07-27
 */

pragma solidity ^0.5.16;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function decimals() external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
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

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;


            bytes32 accountHash
         = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != 0x0 && codehash != accountHash);
    }

    function toPayable(address account)
        internal
        pure
        returns (address payable)
    {
        return address(uint160(account));
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
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

    function getNumTokens() external view returns (uint256);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function getFinalTokens() external view returns (address[] memory tokens);

    function getDenormalizedWeight(address token)
        external
        view
        returns (uint256);

    function getTotalDenormalizedWeight() external view returns (uint256);

    function getNormalizedWeight(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function getSwapFee() external view returns (uint256);

    function getController() external view returns (address);

    function setSwapFee(uint256 swapFee) external;

    function setController(address manager) external;

    function setPublicSwap(bool public_) external;

    function finalize() external;

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external;

    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external;

    function unbind(address token) external;

    function gulp(address token) external;

    function getSpotPrice(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function calcSpotPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 swapFee
    ) external pure returns (uint256 spotPrice);

    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountOut);
}

interface MettalexVault {
    function collateralPerUnit()
        external
        view
        returns (uint256 _collateralPerUnit);

    function collateralFeePerUnit()
        external
        view
        returns (uint256 _collateralFeePerUnit);

    function priceFloor() external view returns (uint256 _priceFloor);

    function priceSpot() external view returns (uint256 _priceSpot);

    function priceCap() external view returns (uint256 _priceCap);

    function mintPositions(uint256 qtyToMint) external;

    function redeemPositions(uint256 qtyToRedeem) external;

    function mintFromCollateralAmount(uint256 _collateralAmount) external;
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
    uint256 public supply; // = 0;

    // OpenZeppelin SDK upgradeable contract
    bool private initialized;

    function initialize(address _controller) public {
        // Single argument init method for use with ganache-cli --deterministic
        // and contracts created in a set order
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

    function initialize(
        address _controller,
        address _want,
        address _balancer,
        address _mettalex_vault,
        address _long_token,
        address _short_token
    ) public {
        // General initializer
        require(!initialized, "Already initialized");
        want = _want;
        balancer = _balancer;
        mettalex_vault = _mettalex_vault;
        long_token = _long_token;
        short_token = _short_token;
        governance = msg.sender;
        controller = _controller;
        breaker = false;
        supply = 0;
    }

    // Constructor is removed when using the OpenZeppelin SDK for upgradeable contracts
    //    constructor(address _controller) public {
    //        governance = msg.sender;
    //        controller = _controller;
    //    }

    function setBreaker(bool _breaker) public {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    function unbind() internal {
        // Unbind tokens from Balancer pool
        Balancer bPool = Balancer(balancer);
        address[] memory tokens = bPool.getCurrentTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            bPool.unbind(tokens[i]);
        }
    }

    function redeemPositions() internal {
        MettalexVault mVault = MettalexVault(mettalex_vault);
        uint256 ltk_qty = IERC20(long_token).balanceOf(address(this));
        uint256 stk_qty = IERC20(short_token).balanceOf(address(this));
        if (stk_qty < ltk_qty) {
            if (stk_qty > 0) {
                mVault.redeemPositions(stk_qty);
            }
        } else if (ltk_qty > 0) {
            mVault.redeemPositions(ltk_qty);
        }
    }

    // Struct containing variables needed for denormalized weight calculation
    // to avoid stack error
    struct PriceInfo {
        uint256 floor;
        uint256 spot;
        uint256 cap;
        uint256 range;
        uint256 C;
        uint256 d_c;
        uint256 d_l;
        uint256 d_s;
        uint256 d;
    }

    function calcDenormWeights(uint256[3] memory bal)
        internal
        returns (uint256[3] memory wt)
    {
        //  Number of collateral tokens per pair of long and short tokens
        MettalexVault mVault = MettalexVault(mettalex_vault);
        PriceInfo memory price;

        price.spot = mVault.priceSpot();
        price.floor = mVault.priceFloor();
        price.cap = mVault.priceCap();
        price.range = price.cap.sub(price.floor);

        //   v = (price - floor)/priceRange
        // 1-v = (cap - price)/priceRange
        price.C = mVault.collateralPerUnit();

        // d =  x_c + C*v*x_l + C*x_s*(1 - v)
        // Try to 'avoid CompilerError: Stack too deep, try removing local variables.'
        // by using single variable to store [x_c, x_l, x_s]
        price.d_c = bal[0];
        price.d_l = price.C.mul(price.spot.sub(price.floor)).mul(bal[1]).div(
            price.range
        );
        price.d_s = price.C.mul(price.cap.sub(price.spot)).mul(bal[2]).div(
            price.range
        );
        price.d = price.d_c.add(price.d_l).add(price.d_s);

        //        new_wts = [
        //            x_c/d,
        //            v*C*x_l/d,
        //            (1-v)*C*x_s/d
        //        ]
        //        new_denorm_wts = [int(100 * tok_wt * 10**18 / 2) for tok_wt in new_wts]

        wt[0] = price.d_c.mul(100 ether).div(2).div(price.d);
        wt[1] = price.d_l.mul(100 ether).div(2).div(price.d);
        wt[2] = price.d_s.mul(100 ether).div(2).div(price.d);

        //        wt[1] = bal[1].mul(100 ether).mul(price.d_l).mul(price.spot.sub(price.floor)).div(price.range).div(d).div(2);
        //        wt[2] = bal[2].mul(100 ether).mul(C).mul(price.cap.sub(price.spot)).div(price.range).div(d).div(2);
        return wt;
    }

    function deposit() external {
        require(breaker == false, "!breaker");
        Balancer bPool = Balancer(balancer);
        MettalexVault mVault = MettalexVault(mettalex_vault);

        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );
        bPool.setPublicSwap(false);

        _depositInternal();

        // Again enable public swap
        bPool.setPublicSwap(true);

        uint256 wantAfterMintandDeposit = IERC20(want).balanceOf(address(this));

        supply = supply.add(
            wantBeforeMintandDeposit.sub(wantAfterMintandDeposit)
        );
    }

    function _depositInternal() private {
        // Get coin token balance and allocate half to minting position tokens
        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );
        uint256 wantToVault = wantBeforeMintandDeposit.div(2);
        IERC20(want).safeApprove(mettalex_vault, 0);
        IERC20(want).safeApprove(mettalex_vault, wantToVault);

        mVault.mintFromCollateralAmount(wantToVault);

        uint256 wantAfterMint = IERC20(want).balanceOf(address(this));

        // Get AMM Pool token balances
        uint256 balancerWant = IERC20(want).balanceOf(address(bpool));
        uint256 balancerLtk = IERC20(long_token).balanceOf(address(bpool));
        uint256 balancerStk = IERC20(short_token).balanceOf(address(bpool));

        // Get Strategy token balances
        uint256 starategyWant = wantAfterMint;
        uint256 strategyLtk = IERC20(long_token).balanceOf(address(this));
        uint256 strategyStk = IERC20(short_token).balanceOf(address(this));

        // Approve transfer to balancer pool
        IERC20(want).safeApprove(balancer, 0);
        IERC20(want).safeApprove(balancer, starategyWant);
        IERC20(long_token).safeApprove(balancer, 0);
        IERC20(long_token).safeApprove(balancer, strategyLtk);
        IERC20(short_token).safeApprove(balancer, 0);
        IERC20(short_token).safeApprove(balancer, strategyStk);

        // Re-calculate de-normalised weights
        // While calculating weights, consider all ( balancer + strategy ) tokens to even out the weights
        uint256[3] memory bal;
        bal[0] = starategyWant.add(balancerWant);
        bal[1] = strategyLtk.add(balancerLtk);
        bal[2] = strategyStk.add(balancerStk);
        uint256[3] memory wt = calcDenormWeights(bal);

        // Rebind tokens to balancer pool again with newly calculated weights
        bPool.rebind(want, starategyWant.add(balancerWant), wt[0]);
        bPool.rebind(long_token, strategyLtk.add(balancerLtk), wt[1]);
        bPool.rebind(short_token, strategyStk.add(balancerStk), wt[2]);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        Balancer bPool = Balancer(balancer);
        MettalexVault mVault = MettalexVault(mettalex_vault);

        // Unbind tokens from Balancer pool
        bPool.setPublicSwap(false);

        unbind();

        redeemPositions();

        uint256 wantAfterPoolRedeem = IERC20(want).balanceOf(address(this));

        // Transfer out required funds to yVault.
        IERC20(want).transfer(Controller(_controller).vaults[want], _amount);

        _depositInternal();

        bPool.setPublicSwap(true);

        supply = supply.sub(_amount);
    }

    function balanceOf() public view returns (uint256) {
        return
            IERC20(want).balanceOf(address(this)).add(
                IERC20(want).balanceOf(address(balancer))
            );
    }

    // This function should return Total valuation of balancer pool.
    // i.e. ( LTK + STK + Coin ) from balancer pool.
    function _getBalancerPoolValue() private {
        return IERC20(want).balanceOf(address(balancer));
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
