pragma solidity ^0.5.16;

import "./interfaces/Ibalancer.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMtlxVault.sol";
import "./interfaces/IYController.sol";
import "./lib/Address.sol";
import "./lib/SignedSafeMath.sol";
import "./lib/SafeMath.sol";
import "./lib/SafeERC20.sol";

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

contract StrategyBalancerMettalexV2 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    // ganache --deterministic USDT
    address public want; // = address(0xCfEB869F69431e42cdB54A4F4f105C19C080A601);

    address public balancer; // = address(0x72Cd8f4504941Bf8c5a21d1Fd83A96499FD71d2C);

    address public mettalexVault; // = address(0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb);
    address public longToken; // = address(0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B);
    address public shortToken; // = address(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);

    address public governance;
    address public controller;
    bool public breaker; // = false;

    // Supply tracks the number of `want` that we have lent out of other distro's
    uint256 public supply; // = 0;
    bool public isBreachHandled;

    // Struct containing variables needed for denormalized weight calculation
    // to avoid stack error
    struct PriceInfo {
        uint256 floor;
        uint256 spot;
        uint256 cap;
        uint256 range;
        uint256 C;
        uint256 dc;
        uint256 dl;
        uint256 ds;
        uint256 d;
    }

    modifier notSettled {
        MettalexVault mVault = MettalexVault(mettalexVault);
        require(!mVault.isSettled(), "mVault is already settled");
        _;
    }

    modifier settled {
        MettalexVault mVault = MettalexVault(mettalexVault);
        require(mVault.isSettled(), "mVault should be settled");
        _;
    }

    modifier callOnce {
        if (!isBreachHandled) {
            _;
        }
    }

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    constructor(
        address _controller,
        address _want,
        address _balancer,
        address _mettalexVault,
        address _longToken,
        address _shortToken
    ) public {
        want = _want;
        balancer = _balancer;
        mettalexVault = _mettalexVault;
        longToken = _longToken;
        shortToken = _shortToken;
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

        Balancer bPool = Balancer(balancer);
        bPool.setController(_controller);
    }

    function _unbind() internal {
        // Unbind tokens from Balancer pool
        Balancer bPool = Balancer(balancer);
        address[] memory tokens = bPool.getCurrentTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            bPool.unbind(tokens[i]);
        }
    }

    function _settle() internal settled {
        MettalexVault mVault = MettalexVault(mettalexVault);
        mVault.settlePositions();
    }

    // Settle all Long and Short tokens held by the contract in case of Commodity breach
    // should be called only once
    function handleBreach() public settled callOnce {
        require(breaker == false, "!breaker");

        isBreachHandled = true;
        // Unbind tokens from Balancer pool
        _unbind();
        _settle();
    }

    function _redeemPositions() internal {
        MettalexVault mVault = MettalexVault(mettalexVault);
        uint256 ltkQty = IERC20(longToken).balanceOf(address(this));
        uint256 stkQty = IERC20(shortToken).balanceOf(address(this));
        if (stkQty < ltkQty) {
            if (stkQty > 0) {
                mVault.redeemPositions(stkQty);
            }
        } else if (ltkQty > 0) {
            mVault.redeemPositions(ltkQty);
        }
    }

    function _calcDenormWeights(uint256[3] memory bal, uint256 spotPrice)
        internal
        view
        returns (uint256[3] memory wt)
    {
        //  Number of collateral tokens per pair of long and short tokens
        MettalexVault mVault = MettalexVault(mettalexVault);
        PriceInfo memory price;

        price.spot = spotPrice; //; mVault.priceSpot();
        price.floor = mVault.priceFloor();
        price.cap = mVault.priceCap();
        price.range = price.cap.sub(price.floor);

        //   v = (price - floor)/priceRange
        // 1-v = (cap - price)/priceRange
        price.C = mVault.collateralPerUnit();

        // d =  x_c + C*v*x_l + C*x_s*(1 - v)
        // Try to 'avoid CompilerError: Stack too deep, try removing local variables.'
        // by using single variable to store [x_c, x_l, x_s]
        price.dc = bal[2];
        price.dl = price.C.mul(price.spot.sub(price.floor)).mul(bal[1]).div(
            price.range
        );
        price.ds = price.C.mul(price.cap.sub(price.spot)).mul(bal[0]).div(
            price.range
        );
        price.d = price.dc.add(price.dl).add(price.ds);

        //        new_wts = [
        //            x_c/d,
        //            v*C*x_l/d,
        //            (1-v)*C*x_s/d
        //        ]
        //        new_denorm_wts = [int(100 * tok_wt * 10**18 / 2) for tok_wt in new_wts]
        wt[0] = price.ds.mul(1 ether).div(price.d);
        wt[1] = price.dl.mul(1 ether).div(price.d);
        wt[2] = price.dc.mul(1 ether).div(price.d);

        uint256 x = (price.range * 1) / 100;

        if (
            price.floor.add(x) >= price.spot || price.cap.sub(x) <= price.spot
        ) {
            wt[0] = wt[0].mul(47).add(1 ether);
            wt[1] = wt[1].mul(47).add(1 ether);
            wt[2] = wt[2].mul(47).add(1 ether);
        } else {
            wt[0] = wt[0].mul(50);
            wt[1] = wt[1].mul(50);
            wt[2] = wt[2].mul(50);
        }

        //        wt[1] = bal[1].mul(100 ether).mul(price.dl).mul(price.spot.sub(price.floor)).div(price.range).div(d).div(2);
        //        wt[2] = bal[2].mul(100 ether).mul(C).mul(price.cap.sub(price.spot)).div(price.range).div(d).div(2);
        return wt;
    }

    function updateSpotAndNormalizeWeights() public notSettled {
        uint256 spotPrice = MettalexVault(mettalexVault).priceSpot();
        _rebalance(spotPrice);
    }

    function _rebalance(uint256 spotPrice) internal {
        // Get AMM Pool token balances
        uint256[3] memory bal;
        bal[0] = IERC20(shortToken).balanceOf(balancer);
        bal[1] = IERC20(longToken).balanceOf(balancer);
        bal[2] = IERC20(want).balanceOf(balancer);

        // Re-calculate de-normalised weights
        uint256[3] memory newWt = _calcDenormWeights(bal, spotPrice);

        address[3] memory tokens = [shortToken, longToken, want];

        // Calculate delta in weights
        Balancer bPool = Balancer(balancer);
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

    function _calculateSpotPrice() public view returns (uint256 spotPrice) {
        MettalexVault mVault = MettalexVault(mettalexVault);
        uint256 floor = mVault.priceFloor();
        uint256 cap = mVault.priceCap();

        //get spot price from balancer pool
        Balancer bPool = Balancer(balancer);
        uint256 priceShort = bPool.getSpotPrice(want, shortToken);
        uint256 priceLong = bPool.getSpotPrice(want, longToken);

        spotPrice = floor.add(
            (cap.sub(floor)).mul(priceLong).div(priceShort.add(priceLong))
        );
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

        Balancer bPool = Balancer(balancer);
        bPool.rebind(tokens[0], balance[0], wt[0]);
        bPool.rebind(tokens[1], balance[1], wt[1]);
        bPool.rebind(tokens[2], balance[2], wt[2]);
    }

    function deposit() external notSettled {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );

        _depositInternal();

        uint256 wantAfterMintandDeposit = IERC20(want).balanceOf(address(this));

        supply = supply.add(
            wantBeforeMintandDeposit.sub(wantAfterMintandDeposit)
        );
    }

    function _mintPositions(uint256 _amount)
        internal
        returns (uint256 ltk, uint256 stk)
    {
        IERC20(want).safeApprove(mettalexVault, 0);
        IERC20(want).safeApprove(mettalexVault, _amount);

        uint256 strategyLtk = IERC20(longToken).balanceOf(address(this));
        uint256 strategyStk = IERC20(shortToken).balanceOf(address(this));

        MettalexVault(mettalexVault).mintFromCollateralAmount(_amount);

        uint256 afterMintLtk = IERC20(longToken).balanceOf(address(this));
        uint256 afterMintStk = IERC20(shortToken).balanceOf(address(this));

        ltk = afterMintLtk.sub(strategyLtk);
        stk = afterMintStk.sub(strategyStk);
    }

    function _depositInternal() private {
        // Get coin token balance and allocate half to minting position tokens
        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );
        uint256 wantToVault = wantBeforeMintandDeposit.div(2);
        _mintPositions(wantToVault);

        uint256 wantAfterMint = IERC20(want).balanceOf(address(this));

        // Get AMM Pool token balances
        uint256 balancerWant = IERC20(want).balanceOf(balancer);
        uint256 balancerLtk = IERC20(longToken).balanceOf(balancer);
        uint256 balancerStk = IERC20(shortToken).balanceOf(balancer);

        // Get Strategy token balances
        uint256 strategyWant = wantAfterMint;
        uint256 strategyLtk = IERC20(longToken).balanceOf(address(this));
        uint256 strategyStk = IERC20(shortToken).balanceOf(address(this));

        // Approve transfer to balancer pool
        IERC20(want).safeApprove(balancer, 0);
        IERC20(want).safeApprove(balancer, strategyWant);
        IERC20(longToken).safeApprove(balancer, 0);
        IERC20(longToken).safeApprove(balancer, strategyLtk);
        IERC20(shortToken).safeApprove(balancer, 0);
        IERC20(shortToken).safeApprove(balancer, strategyStk);

        // Re-calculate de-normalised weights
        // While calculating weights, consider all ( balancer + strategy ) tokens to even out the weights
        uint256[3] memory bal;
        bal[0] = strategyStk.add(balancerStk);
        bal[1] = strategyLtk.add(balancerLtk);
        bal[2] = strategyWant.add(balancerWant);
        uint256[3] memory wt = _calcDenormWeights(
            bal,
            MettalexVault(mettalexVault).priceSpot()
        );

        Balancer bPool = Balancer(balancer);
        // Rebind tokens to balancer pool again with newly calculated weights
        bool isWantBound = bPool.isBound(want);
        bool isStkBound = bPool.isBound(shortToken);
        bool isLtkBound = bPool.isBound(longToken);

        if (isStkBound != true && isLtkBound != true && isWantBound != true) {
            bPool.bind(shortToken, strategyStk.add(balancerStk), wt[0]);
            bPool.bind(longToken, strategyLtk.add(balancerLtk), wt[1]);
            bPool.bind(want, strategyWant.add(balancerWant), wt[2]);
        } else {
            int256[3] memory delta;
            address[3] memory tokens = [shortToken, longToken, want];

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

        MettalexVault mVault = MettalexVault(mettalexVault);
        if (mVault.isSettled()) {
            handleBreach();
            IERC20(want).transfer(Controller(controller).vaults(want), _amount);
        } else {
            _unbind();

            _redeemPositions();

            // Transfer out required funds to yVault.
            IERC20(want).transfer(Controller(controller).vaults(want), _amount);

            _depositInternal();
        }

        supply = supply.sub(_amount);
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(address _token) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");
        require(address(_token) != want, "Want");
        require(address(_token) != longToken, "LTOK");
        require(address(_token) != shortToken, "STOK");

        balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(controller, balance);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");

        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));
        address _vault = Controller(controller).vaults(want);

        uint256 ltkDust = IERC20(longToken).balanceOf(address(this));
        uint256 stkDust = IERC20(shortToken).balanceOf(address(this));

        // additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);

        IERC20(longToken).safeTransfer(controller, ltkDust);
        IERC20(shortToken).safeTransfer(controller, stkDust);
    }

    function _withdrawAll() internal {
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
        bool hasLong = IERC20(longToken).balanceOf(address(this)) > 0;
        bool hasShort = IERC20(shortToken).balanceOf(address(this)) > 0;
        if (hasLong || hasShort) {
            handleBreach();
        }

        mettalexVault = _vault;
        longToken = _ltk;
        shortToken = _stk;

        _depositInternal();

        isBreachHandled = false;
    }

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(tokenAmountIn > 0, "ERR_AMOUNT_IN");

        //get tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), tokenAmountIn);

        Balancer bPool = Balancer(balancer);
        bPool.setPublicSwap(true);

        if (tokenIn == want) {
            tokenAmountOut = _swapFromCoin(
                tokenAmountIn,
                tokenOut,
                minAmountOut
            );
        } else if (tokenOut == want) {
            tokenAmountOut = _swapToCoin(tokenIn, tokenAmountIn, minAmountOut);
        } else {
            tokenAmountOut = _swapPositions(
                tokenIn,
                tokenAmountIn,
                tokenOut,
                minAmountOut
            );
        }

        emit LOG_SWAP(
            msg.sender,
            tokenIn,
            tokenOut,
            tokenAmountIn,
            tokenAmountOut
        );
        bPool.setPublicSwap(false);
    }

    function _swapFromCoin(
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut
    ) internal returns (uint256 tokenAmountOut) {
        require(
            tokenOut == longToken || tokenOut == shortToken,
            "ERR_TOKEN_OUT"
        );

        Balancer bPool = Balancer(balancer);
        IERC20(want).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, ) = bPool.swapExactAmountIn(
            want,
            tokenAmountIn,
            tokenOut,
            1,
            uint256(-1)
        );

        //Rebalance Pool
        uint256 newSpotPrice = _calculateSpotPrice();
        _rebalance(newSpotPrice);

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(tokenOut).transfer(msg.sender, tokenAmountOut);
    }

    function _swapToCoin(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minAmountOut
    ) internal returns (uint256 tokenAmountOut) {
        require(tokenIn == longToken || tokenIn == shortToken, "ERR_TOKEN_IN");

        Balancer bPool = Balancer(balancer);
        IERC20(tokenIn).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, ) = bPool.swapExactAmountIn(
            tokenIn,
            tokenAmountIn,
            want,
            minAmountOut,
            uint256(-1)
        );

        //Rebalance Pool
        uint256 newSpotPrice = _calculateSpotPrice();
        _rebalance(newSpotPrice);

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(want).transfer(msg.sender, tokenAmountOut);
    }

    function _swapPositions(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut
    ) internal returns (uint256 tokenAmountOut) {
        require(tokenIn != tokenOut, "ERR_SAME_TOKEN_SWAP");
        require(tokenIn == longToken || tokenIn == shortToken, "ERR_TOKEN_IN");
        require(
            tokenOut == longToken || tokenOut == shortToken,
            "ERR_TOKEN_OUT"
        );

        Balancer bPool = Balancer(balancer);
        IERC20(tokenIn).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, ) = bPool.swapExactAmountIn(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            uint256(-1)
        );

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(tokenOut).transfer(msg.sender, tokenAmountOut);
    }

    function balanceOf() external view returns (uint256) {
        uint256 bpoolValuation = _getBalancerPoolValue();
        return IERC20(want).balanceOf(address(this)).add(bpoolValuation);
    }

    // This function should return Total valuation of balancer pool.
    // i.e. ( LTK + STK + Coin ) from balancer pool.
    function _getBalancerPoolValue() internal view returns (uint256) {
        uint256 poolStkBalance = IERC20(shortToken).balanceOf(
            address(balancer)
        );
        uint256 poolLtkBalance = IERC20(longToken).balanceOf(address(balancer));
        uint256 collateralPerUnit = MettalexVault(mettalexVault)
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
        Balancer bpool = Balancer(balancer);

        require(bpool.isBound(fromToken));
        require(bpool.isBound(toToken));
        uint256 swapFee = bpool.getSwapFee();

        uint256 tokenBalanceIn = bpool.getBalance(fromToken);
        uint256 tokenBalanceOut = bpool.getBalance(toToken);

        uint256 tokenWeightIn = bpool.getDenormalizedWeight(fromToken);
        uint256 tokenWeightOut = bpool.getDenormalizedWeight(toToken);

        tokensReturned = bpool.calcOutGivenIn(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            fromTokenAmount,
            swapFee
        );

        uint256 spotPrice = bpool.getSpotPrice(fromToken, toToken);
        uint256 effectivePrice = ((fromTokenAmount * 10**18) / tokensReturned);
        priceImpact = ((effectivePrice - spotPrice) * 10**18) / spotPrice;
    }

    function getExpectedInAmount(
        address bPoolAddress,
        address fromToken,
        address toToken,
        uint256 toTokenAmount
    ) public view returns (uint256 tokensReturned, uint256 priceImpact) {
        Balancer bpool = Balancer(balancer);

        require(bpool.isBound(fromToken));
        require(bpool.isBound(toToken));
        uint256 swapFee = bpool.getSwapFee();

        uint256 tokenBalanceIn = bpool.getBalance(fromToken);
        uint256 tokenBalanceOut = bpool.getBalance(toToken);

        uint256 tokenWeightIn = bpool.getDenormalizedWeight(fromToken);
        uint256 tokenWeightOut = bpool.getDenormalizedWeight(toToken);

        tokensReturned = bpool.calcInGivenOut(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            toTokenAmount,
            swapFee
        );

        uint256 spotPrice = bpool.getSpotPrice(fromToken, toToken);
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

    function setSwapFee(uint256 _swapFee) external {
        require(msg.sender == governance, "!governance");
        Balancer(balancer).setSwapFee(_swapFee);
    }

    /********** BPool Methods for UI *********/
    function getBalance(address token) external view returns (uint256) {
        return Balancer(balancer).getBalance(token);
    }

    function getSwapFee() external view returns (uint256) {
        return Balancer(balancer).getSwapFee();
    }

    function isBound(address token) external view returns (bool) {
        return Balancer(balancer).isBound(token);
    }
}
