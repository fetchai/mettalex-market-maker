pragma solidity ^0.5.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IBalancer.sol";
import "../interfaces/IMettalexVault.sol";
import "../interfaces/IYController.sol";

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

contract StrategyBalancerMettalexV1 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

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
    bool public isBreachHandled;

    modifier notSettled {
        IMettalexVault mVault = IMettalexVault(mettalex_vault);
        require(!mVault.isSettled(), "mVault is already settled");
        _;
    }

    modifier settled {
        IMettalexVault mVault = IMettalexVault(mettalex_vault);
        require(mVault.isSettled(), "mVault should be settled");
        _;
    }

    modifier callOnce {
        if (!isBreachHandled) {
            _;
        }
    }

    constructor(
        address _controller,
        address _want,
        address _balancer,
        address _mettalex_vault,
        address _long_token,
        address _short_token
    ) public {
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

    function setBreaker(bool _breaker) public {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    function updatePoolController(address _controller) public {
        require(msg.sender == governance, "!governance");

        IBalancer bPool = IBalancer(balancer);
        bPool.setController(_controller);
    }

    function _unbind() internal {
        // Unbind tokens from Balancer pool
        IBalancer bPool = IBalancer(balancer);
        address[] memory tokens = bPool.getCurrentTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            bPool.unbind(tokens[i]);
        }
    }

    function _settle() internal settled {
        IMettalexVault mVault = IMettalexVault(mettalex_vault);
        mVault.settlePositions();
    }

    // Settle all Long and Short tokens held by the contract in case of Commodity breach
    // should be called only once
    function handleBreach() public settled callOnce {
        require(breaker == false, "!breaker");

        isBreachHandled = true;

        IBalancer bPool = IBalancer(balancer);

        // Set public swap to false
        bPool.setPublicSwap(false);

        // Unbind tokens from Balancer pool
        _unbind();
        _settle();
    }

    function _redeemPositions() internal {
        IMettalexVault mVault = IMettalexVault(mettalex_vault);
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

    function _calcDenormWeights(uint256[3] memory bal)
        internal
        view
        returns (uint256[3] memory wt)
    {
        //  Number of collateral tokens per pair of long and short tokens
        IMettalexVault mVault = IMettalexVault(mettalex_vault);
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
        price.d_c = bal[2];
        price.d_l = price.C.mul(price.spot.sub(price.floor)).mul(bal[1]).div(
            price.range
        );
        price.d_s = price.C.mul(price.cap.sub(price.spot)).mul(bal[0]).div(
            price.range
        );
        price.d = price.d_c.add(price.d_l).add(price.d_s);

        //        new_wts = [
        //            x_c/d,
        //            v*C*x_l/d,
        //            (1-v)*C*x_s/d
        //        ]
        //        new_denorm_wts = [int(100 * tok_wt * 10**18 / 2) for tok_wt in new_wts]

        wt[0] = price.d_s.mul(47 ether).div(price.d).add(1 ether);
        wt[1] = price.d_l.mul(47 ether).div(price.d).add(1 ether);
        wt[2] = price.d_c.mul(47 ether).div(price.d).add(1 ether);

        //        wt[1] = bal[1].mul(100 ether).mul(price.d_l).mul(price.spot.sub(price.floor)).div(price.range).div(d).div(2);
        //        wt[2] = bal[2].mul(100 ether).mul(C).mul(price.cap.sub(price.spot)).div(price.range).div(d).div(2);
        return wt;
    }

    function updateSpotAndNormalizeWeights() external notSettled {
        // Get AMM Pool token balances
        uint256 balancerStk = IERC20(short_token).balanceOf(balancer);
        uint256 balancerLtk = IERC20(long_token).balanceOf(balancer);
        uint256 balancerWant = IERC20(want).balanceOf(balancer);

        // Re-calculate de-normalised weights
        uint256[3] memory bal;
        bal[0] = balancerStk;
        bal[1] = balancerLtk;
        bal[2] = balancerWant;
        uint256[3] memory newWt = _calcDenormWeights(bal);

        address[3] memory tokens = [short_token, long_token, want];

        // Calculate delta in weights
        IBalancer bPool = IBalancer(balancer);
        int256[3] memory delta;

        // Max denorm value is compatible with int256
        delta[0] = int256(newWt[0]).sub(
            int256(bPool.getDenormalizedWeight(tokens[0]))
        );
        delta[1] = int256(newWt[1]).sub(
            int256(bPool.getDenormalizedWeight(tokens[1]))
        );
        delta[2] = int256(newWt[2]).sub(
            int256(bPool.getDenormalizedWeight(tokens[2]))
        );

        _sortAndRebind(delta, newWt, bal, tokens);
    }

    function _sortAndRebind(
        int256[3] memory delta,
        uint256[3] memory wt,
        uint256[3] memory balance,
        address[3] memory tokens
    ) internal {
        if (delta[0] > delta[1]) {
            int256 tempDelta = delta[0];
            delta[0] = delta[1];
            delta[1] = tempDelta;

            uint256 tempBalance = balance[0];
            balance[0] = balance[1];
            balance[1] = tempBalance;

            uint256 tempWt = wt[0];
            wt[0] = wt[1];
            wt[1] = tempWt;

            address tempToken = tokens[0];
            tokens[0] = tokens[1];
            tokens[1] = tempToken;
        }

        if (delta[1] > delta[2]) {
            int256 tempDelta = delta[1];
            delta[1] = delta[2];
            delta[2] = tempDelta;

            uint256 tempBalance = balance[1];
            balance[1] = balance[2];
            balance[2] = tempBalance;

            uint256 tempWt = wt[1];
            wt[1] = wt[2];
            wt[2] = tempWt;

            address tempToken = tokens[1];
            tokens[1] = tokens[2];
            tokens[2] = tempToken;
        }

        if (delta[0] > delta[1]) {
            int256 tempDelta = delta[0];
            delta[0] = delta[1];
            delta[1] = tempDelta;

            uint256 tempBalance = balance[0];
            balance[0] = balance[1];
            balance[1] = tempBalance;

            uint256 tempWt = wt[0];
            wt[0] = wt[1];
            wt[1] = tempWt;

            address tempToken = tokens[0];
            tokens[0] = tokens[1];
            tokens[1] = tempToken;
        }

        IBalancer bPool = IBalancer(balancer);
        bPool.rebind(tokens[0], balance[0], wt[0]);
        bPool.rebind(tokens[1], balance[1], wt[1]);
        bPool.rebind(tokens[2], balance[2], wt[2]);
    }

    function deposit() external notSettled {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");
        IBalancer bPool = IBalancer(balancer);

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

        IMettalexVault(mettalex_vault).mintFromCollateralAmount(wantToVault);

        uint256 wantAfterMint = IERC20(want).balanceOf(address(this));

        // Get AMM Pool token balances
        uint256 balancerWant = IERC20(want).balanceOf(balancer);
        uint256 balancerLtk = IERC20(long_token).balanceOf(balancer);
        uint256 balancerStk = IERC20(short_token).balanceOf(balancer);

        // Get Strategy token balances
        uint256 strategyWant = wantAfterMint;
        uint256 strategyLtk = IERC20(long_token).balanceOf(address(this));
        uint256 strategyStk = IERC20(short_token).balanceOf(address(this));

        // Approve transfer to balancer pool
        IERC20(want).safeApprove(balancer, 0);
        IERC20(want).safeApprove(balancer, strategyWant);
        IERC20(long_token).safeApprove(balancer, 0);
        IERC20(long_token).safeApprove(balancer, strategyLtk);
        IERC20(short_token).safeApprove(balancer, 0);
        IERC20(short_token).safeApprove(balancer, strategyStk);

        // Re-calculate de-normalised weights
        // While calculating weights, consider all ( balancer + strategy ) tokens to even out the weights
        uint256[3] memory bal;
        bal[0] = strategyStk.add(balancerStk);
        bal[1] = strategyLtk.add(balancerLtk);
        bal[2] = strategyWant.add(balancerWant);
        uint256[3] memory wt = _calcDenormWeights(bal);

        IBalancer bPool = IBalancer(balancer);
        // Rebind tokens to balancer pool again with newly calculated weights
        bool isWantBound = bPool.isBound(want);
        bool isStkBound = bPool.isBound(short_token);
        bool isLtkBound = bPool.isBound(long_token);

        if (isStkBound != true && isLtkBound != true && isWantBound != true) {
            bPool.bind(short_token, strategyStk.add(balancerStk), wt[0]);
            bPool.bind(long_token, strategyLtk.add(balancerLtk), wt[1]);
            bPool.bind(want, strategyWant.add(balancerWant), wt[2]);
        } else {
            int256[3] memory delta;
            address[3] memory tokens = [short_token, long_token, want];

            // Max denorm value is compatible with int256
            delta[0] = int256(wt[0]).sub(
                int256(bPool.getDenormalizedWeight(tokens[0]))
            );
            delta[1] = int256(wt[1]).sub(
                int256(bPool.getDenormalizedWeight(tokens[1]))
            );
            delta[2] = int256(wt[2]).sub(
                int256(bPool.getDenormalizedWeight(tokens[2]))
            );

            _sortAndRebind(delta, wt, bal, tokens);
        }
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        // check if breached: return
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        IMettalexVault mVault = IMettalexVault(mettalex_vault);
        if (mVault.isSettled()) {
            handleBreach();
            IERC20(want).transfer(
                IYController(controller).vaults(want),
                _amount
            );
        } else {
            IBalancer bPool = IBalancer(balancer);

            // Unbind tokens from Balancer pool
            bPool.setPublicSwap(false);

            _unbind();

            _redeemPositions();

            // Transfer out required funds to yVault.
            IERC20(want).transfer(
                IYController(controller).vaults(want),
                _amount
            );

            _depositInternal();

            bPool.setPublicSwap(true);
        }

        supply = supply.sub(_amount);
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(address _token) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");
        require(address(_token) != want, "Want");
        require(address(_token) != long_token, "LTOK");
        require(address(_token) != short_token, "STOK");

        balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(controller, balance);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");

        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));
        address _vault = IYController(controller).vaults(want);

        uint256 ltkDust = IERC20(long_token).balanceOf(address(this));
        uint256 stkDust = IERC20(short_token).balanceOf(address(this));

        // additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);

        IERC20(long_token).safeTransfer(controller, ltkDust);
        IERC20(short_token).safeTransfer(controller, stkDust);
    }

    function _withdrawAll() internal {
        IBalancer bPool = IBalancer(balancer);

        // Unbind tokens from Balancer pool
        bPool.setPublicSwap(false);

        uint256 _before = IERC20(want).balanceOf(address(this));

        _unbind();
        _redeemPositions();

        uint256 _after = IERC20(want).balanceOf(address(this));

        uint256 _diff = _after.sub(_before);
        if (_diff > supply) {
            // Pool made too much profit, so we reset to 0 to avoid revert
            supply = 0;
        } else {
            supply = supply.sub(_after.sub(_before));
        }
    }

    // Update Contract addresses after breach
    function updateCommodityAfterBreach(
        address _vault,
        address _ltk,
        address _stk
    ) external settled {
        require(msg.sender == governance, "!governance");
        bool hasLong = IERC20(long_token).balanceOf(address(this)) > 0;
        bool hasShort = IERC20(short_token).balanceOf(address(this)) > 0;
        if (hasLong || hasShort) {
            handleBreach();
        }

        mettalex_vault = _vault;
        long_token = _ltk;
        short_token = _stk;

        _depositInternal();

        // public swap was set to false during handle breach
        IBalancer bPool = IBalancer(balancer);
        bPool.setPublicSwap(true);

        isBreachHandled = false;
    }

    function balanceOf() external view returns (uint256) {
        uint256 bpoolValuation = _getBalancerPoolValue();
        return IERC20(want).balanceOf(address(this)).add(bpoolValuation);
    }

    // This function should return Total valuation of balancer pool.
    // i.e. ( LTK + STK + Coin ) from balancer pool.
    function _getBalancerPoolValue() internal view returns (uint256) {
        uint256 poolStkBalance = IERC20(short_token).balanceOf(
            address(balancer)
        );
        uint256 poolLtkBalance = IERC20(long_token).balanceOf(
            address(balancer)
        );
        uint256 collateralPerUnit = IMettalexVault(mettalex_vault)
            .collateralPerUnit();
        uint256 totalValuation;
        if (poolStkBalance >= poolLtkBalance) {
            totalValuation = IERC20(want).balanceOf(address(balancer)).add(
                poolLtkBalance.mul(collateralPerUnit)
            );
        } else {
            totalValuation = IERC20(want).balanceOf(address(balancer)).add(
                poolStkBalance.mul(collateralPerUnit)
            );
        }
        return totalValuation;
    }

    function getExpectedOutAmount(
        address bPoolAddress,
        address fromToken,
        address toToken,
        uint256 fromTokenAmount
    ) public view returns (uint256 tokensReturned, uint256 priceImpact) {
        require(IBalancer(bPoolAddress).isBound(fromToken));
        require(IBalancer(bPoolAddress).isBound(toToken));
        uint256 swapFee = IBalancer(bPoolAddress).getSwapFee();

        uint256 tokenBalanceIn = IBalancer(bPoolAddress).getBalance(fromToken);
        uint256 tokenBalanceOut = IBalancer(bPoolAddress).getBalance(toToken);

        uint256 tokenWeightIn = IBalancer(bPoolAddress).getDenormalizedWeight(
            fromToken
        );
        uint256 tokenWeightOut = IBalancer(bPoolAddress).getDenormalizedWeight(
            toToken
        );

        tokensReturned = IBalancer(bPoolAddress).calcOutGivenIn(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            fromTokenAmount,
            swapFee
        );

        uint256 spotPrice = IBalancer(bPoolAddress).getSpotPrice(
            fromToken,
            toToken
        );
        uint256 effectivePrice = ((fromTokenAmount * 10**18) / tokensReturned);
        priceImpact = ((effectivePrice - spotPrice) * 10**18) / spotPrice;
    }

    function getExpectedInAmount(
        address bPoolAddress,
        address fromToken,
        address toToken,
        uint256 toTokenAmount
    ) public view returns (uint256 tokensReturned, uint256 priceImpact) {
        require(IBalancer(bPoolAddress).isBound(fromToken));
        require(IBalancer(bPoolAddress).isBound(toToken));
        uint256 swapFee = IBalancer(bPoolAddress).getSwapFee();

        uint256 tokenBalanceIn = IBalancer(bPoolAddress).getBalance(fromToken);
        uint256 tokenBalanceOut = IBalancer(bPoolAddress).getBalance(toToken);

        uint256 tokenWeightIn = IBalancer(bPoolAddress).getDenormalizedWeight(
            fromToken
        );
        uint256 tokenWeightOut = IBalancer(bPoolAddress).getDenormalizedWeight(
            toToken
        );

        tokensReturned = IBalancer(bPoolAddress).calcInGivenOut(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            toTokenAmount,
            swapFee
        );

        uint256 spotPrice = IBalancer(bPoolAddress).getSpotPrice(
            fromToken,
            toToken
        );
        uint256 effectivePrice = ((tokensReturned * 10**18) / toTokenAmount);
        priceImpact = ((effectivePrice - spotPrice) * 10**18) / spotPrice;
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
