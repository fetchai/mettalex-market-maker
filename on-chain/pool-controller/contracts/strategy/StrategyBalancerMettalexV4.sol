pragma solidity ^0.5.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IBalancer.sol";
import "../interfaces/IMettalexVault.sol";
import "../interfaces/IYController.sol";

/**
 * @title StrategyBalancerMettalexV4
 * @notice A strategy must implement the following calls:
 * 1. deposit()
 * 2. withdraw(address) - must exclude any tokens used in the yield - Controller role
 *    withdraw should return to Controller
 * 3. withdraw(uint) - Controller role - withdraw should always return to vault
 * 4. withdrawAll() - Controller role - withdraw should always return to vault
 * 5. balanceOf()
 * Where possible, strategies must remain as immutable as possible, instead of updating
 * variables, we update the contract by linking it in the controller
 * @dev Strategy ~ 50% USDT to LTK + STK
 * USDT + LTK + STK into balancer
 * (No yield farming, just Balancer pool fees)
 */
contract StrategyBalancerMettalexV4 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

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

    // Supply tracks the number of `want` that we have lent out of other distro's
    uint256 public supply;

    uint256 private constant ORACLE_REBALANCE = 1;
    uint256 private constant DEPOSIT_REBALANCE = 2;
    //includes swap and withdraw
    uint256 private constant OTHER_REBALANCE = 3;

    address public want;
    address public balancer;
    address public mettalexVault;
    address public longToken;
    address public shortToken;
    address public governance;
    address public controller;

    bool public isBreachHandled;
    bool public breaker;

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    /**
     * @dev The Strategy constructor sets initial values
     * @param _controller address The address of Strategy Controller (IYController)
     * @param _want address The address of Want token
     * @param _balancer address The address of Balancer Pool
     * @param _mettalexVault address The Mettalex vault address connected with the current commodity
     * @param _longToken address The long position token address
     * @param _shortToken address The short position token address
     */
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

    /**
     * @dev Throws if breach already handled after commodity settled
     */
    modifier callOnce {
        if (!isBreachHandled) {
            _;
        }
    }

    /**
     * @dev Throws if vault contract is not settled
     */
    modifier notSettled {
        IMettalexVault mVault = IMettalexVault(mettalexVault);
        require(!mVault.isSettled(), "mVault is already settled");
        _;
    }

    /**
     * @dev Throws if vault contract is settled
     */
    modifier settled {
        IMettalexVault mVault = IMettalexVault(mettalexVault);
        require(mVault.isSettled(), "mVault should be settled");
        _;
    }

    /**
     * @dev Used to deposit and bind/rebalance the balancer pool
     * @dev Can be called by controller only
     */
    function deposit() external notSettled {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );

        uint256 spotPrice = _calculateSpotPrice(
            DEPOSIT_REBALANCE,
            wantBeforeMintandDeposit
        );
        _depositInternal(spotPrice);

        uint256 wantAfterMintandDeposit = IERC20(want).balanceOf(address(this));

        supply = supply.add(
            wantBeforeMintandDeposit.sub(wantAfterMintandDeposit)
        );
    }

    /**
     * @dev Used to withdraw partial funds, normally used with a vault withdrawal
     * @dev Can be called by controller only
     * @param _amount uint256 The amount of want to withdraw
     */
    function withdraw(uint256 _amount) external {
        // check if breached: return
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        IMettalexVault mVault = IMettalexVault(mettalexVault);
        if (mVault.isSettled()) {
            handleBreach();
            IERC20(want).transfer(
                IYController(controller).vaults(want),
                _amount
            );
        } else {
            _unbind();

            _redeemPositions();

            // Transfer out required funds to yVault.
            IERC20(want).transfer(
                IYController(controller).vaults(want),
                _amount
            );

            uint256 spotPrice = _calculateSpotPrice(OTHER_REBALANCE, 0);
            _depositInternal(spotPrice);
        }

        supply = supply.sub(_amount);
    }

    /**
     * @dev Used for creating additional rewards from dust
     * @dev Can be called by controller only
     * @param _token address The address of token to collect
     * @return The balance of this contract for given token address
     */
    function withdraw(address _token) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");
        require(address(_token) != want, "Want");
        require(address(_token) != longToken, "LTOK");
        require(address(_token) != shortToken, "STOK");

        balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(controller, balance);
    }

    /**
     * @dev Used to withdraw all funds, normally used when migrating strategies
     * @dev Can be called by controller only
     * @return The balance of want transferred to controller
     */
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");

        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));
        address _vault = IYController(controller).vaults(want);

        uint256 ltkDust = IERC20(longToken).balanceOf(address(this));
        uint256 stkDust = IERC20(shortToken).balanceOf(address(this));

        // additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);

        IERC20(longToken).safeTransfer(controller, ltkDust);
        IERC20(shortToken).safeTransfer(controller, stkDust);
    }

    /**
     * @dev Used to swap tokens from Balancer pool
     * @dev method signature same as swapExactAmountIn() in BPool
     * @param tokenIn address The address of token to swap (_from)
     * @param tokenAmountIn uint256 The amount of token to swap
     * @param tokenOut address The address of token to receive after swap (_to)
     * @param minAmountOut uint256 The amount expected after swapping _from token
     * @param maxPrice uint256 max price after swap
     * @return The amount of _to token returned to user
     * @return The spot price after token swap
     */
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

        IBalancer bPool = IBalancer(balancer);
        bPool.setPublicSwap(true);

        if (tokenIn == want) {
            (tokenAmountOut, spotPriceAfter) = _swapFromCoin(
                tokenAmountIn,
                tokenOut,
                minAmountOut,
                maxPrice
            );
        } else if (tokenOut == want) {
            (tokenAmountOut, spotPriceAfter) = _swapToCoin(
                tokenIn,
                tokenAmountIn,
                minAmountOut,
                maxPrice
            );
        } else {
            (tokenAmountOut, spotPriceAfter) = _swapPositions(
                tokenIn,
                tokenAmountIn,
                tokenOut,
                minAmountOut,
                maxPrice
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

    /**
     * @dev Used to rebalance the Balancer pool according to new spot
     * price updated in vault
     */
    function updateSpotAndNormalizeWeights() external notSettled {
        _unbind();
        _redeemPositions();

        uint256 spotPrice = _calculateSpotPrice(ORACLE_REBALANCE, 0);
        _depositInternal(spotPrice);
    }

    /**
     * @dev Used to settle all Long and Short tokens held by the contract
     * in case of Commodity breach
     * @dev Should be called only once (before updating commodity addresses)
     * @dev isBreachHandled updated in updateCommodityAfterBreach() with same BPool and Strategy
     * but new position tokens and vault
     */
    function handleBreach() public settled callOnce {
        require(breaker == false, "!breaker");

        isBreachHandled = true;
        // Unbind tokens from Balancer pool
        _unbind();
        _settle();
    }

    /**
     * @dev Used to update Contract addresses after breach
     * @dev Can be called by governance only
     * @param _vault address The new address of vault
     * @param _ltk address The new address of long token
     * @param _stk address The new address of short token
     */
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

        uint256 spotPrice = _calculateSpotPrice(OTHER_REBALANCE, 0);
        _depositInternal(spotPrice);

        isBreachHandled = false;
    }

    /**
     * @dev Used to get balance of strategy in terms of want
     * @dev Gets pool value (LTK + STK + USDT (want)) in terms of USDT and
     * adds the amount to this contract balance.
     * @return The balance of strategy and bpool in terms of want
     */
    function balanceOf() external view returns (uint256) {
        uint256 bpoolValuation = _getBalancerPoolValue();
        return IERC20(want).balanceOf(address(this)).add(bpoolValuation);
    }

    /**
     * @dev Used to update governance address
     * @dev Can be called by governance only
     * @param _governance address The address of new governance
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /**
     * @dev Used to update controller for strategy
     * @dev Can be called by governance only
     * @param _controller address The address of new controller
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    /**
     * @dev Used to update swap fee in balancer pool
     * @dev Can be called by governance only
     * @param _swapFee uint256 The new swap fee
     */
    function setSwapFee(uint256 _swapFee) external {
        require(msg.sender == governance, "!governance");
        IBalancer(balancer).setSwapFee(_swapFee);
    }

    /**
     * @dev Used to pause the contract functions on which break is applied
     * @dev Can be called by governance only
     * @param _breaker bool The boolean value indicating contract is paused or not
     */
    function setBreaker(bool _breaker) public {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    /**
     * @dev Used to update balancer pool controller address
     * @dev Can be called by governance only
     * @param _controller address The address of new controller
     */
    function updatePoolController(address _controller) public {
        require(msg.sender == governance, "!governance");

        IBalancer bPool = IBalancer(balancer);
        bPool.setController(_controller);
    }

    /********** BPool Methods for UI *********/
    /**
     * @dev Used to get balance of token in balancer pool connected with this strategy
     * @param token address The address of token
     * @return The balance of given token in balancer pool
     */
    function getBalance(address token) external view returns (uint256) {
        return IBalancer(balancer).getBalance(token);
    }

    /**
     * @dev Used to get swap fee of the balancer pool connected with this strategy
     * @return The swap fee of balancer pool
     */
    function getSwapFee() external view returns (uint256) {
        return IBalancer(balancer).getSwapFee();
    }

    /**
     * @dev Used to check if token is bounded to the balancer pool connected with this strategy
     * @param token address The address of token
     * @return If given token is bounded to balancer pool or not
     */
    function isBound(address token) external view returns (bool) {
        return IBalancer(balancer).isBound(token);
    }

    /**
     * @dev Used to get expected _to amount after swapping given amount
     * of _from token
     * @param fromToken address The address of _from token
     * @param toToken address The address of _to token
     * @param fromTokenAmount uint256 The amount of _from token to swap
     * @return The _to amount expected after swapping given amount of _from token
     * @return The price impact in swapping
     */
    function getExpectedOutAmount(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount
    ) public view returns (uint256 tokensReturned, uint256 priceImpact) {
        IBalancer bpool = IBalancer(balancer);

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

    /**
     * @dev Used to get expected amount of _from token needed for getting
     * exact amount of _to token
     * @param fromToken address The address of _from token
     * @param toToken address The address of _to token
     * @param toTokenAmount uint256 The amount of _from token to swap
     * @return The _from amount to be swapped to get toTokenAmount of _to token
     * @return The price impact in swapping
     */
    function getExpectedInAmount(
        address fromToken,
        address toToken,
        uint256 toTokenAmount
    ) public view returns (uint256 tokensReturned, uint256 priceImpact) {
        IBalancer bpool = IBalancer(balancer);

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

    function _calculateSpotPrice(uint256 typeOfRebalance, uint256 amountAdded)
        internal
        view
        returns (uint256 spotPrice)
    {
        if (
            !IBalancer(balancer).isBound(want) ||
            typeOfRebalance == ORACLE_REBALANCE
        ) {
            spotPrice = IMettalexVault(mettalexVault).priceSpot();
            return spotPrice;
        }

        uint256 floor = IMettalexVault(mettalexVault).priceFloor();
        uint256 cap = IMettalexVault(mettalexVault).priceCap();

        //get spot price from balancer pool
        uint256 priceShort = IBalancer(balancer).getSpotPrice(want, shortToken);
        uint256 priceLong = IBalancer(balancer).getSpotPrice(want, longToken);

        uint256 ammSpot = floor.add(
            (cap.sub(floor)).mul(priceLong).div(priceShort.add(priceLong))
        );

        if (typeOfRebalance == OTHER_REBALANCE) return ammSpot;

        //bO and bt
        uint256 amount = IERC20(shortToken).balanceOf(balancer);

        if (
            IERC20(longToken).balanceOf(balancer) <=
            IERC20(shortToken).balanceOf(balancer)
        ) {
            amount = IERC20(longToken).balanceOf(balancer);
        }

        uint256 balanceOracle = IERC20(want).balanceOf(balancer) +
            amount.mul(IMettalexVault(mettalexVault).collateralPerUnit());

        uint256 balanceTrade = balanceOracle.add(amountAdded); //want added

        //amm_wt and oracle_wt
        uint256 ammWeight = balanceOracle.mul(1 ether).div(balanceTrade);
        uint256 oracleWeight = amountAdded.mul(1 ether).div(balanceTrade);

        uint256 oracleSpot = IMettalexVault(mettalexVault).priceSpot();

        spotPrice = ((ammSpot.mul(ammWeight)).add(oracleSpot.mul(oracleWeight)))
            .div(1 ether);

        return spotPrice;
    }

    function _redeemPositions() internal {
        IMettalexVault mVault = IMettalexVault(mettalexVault);
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

    function _unbind() internal {
        // Unbind tokens from Balancer pool
        IBalancer bPool = IBalancer(balancer);
        address[] memory tokens = bPool.getCurrentTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            bPool.unbind(tokens[i]);
        }
    }

    function _settle() internal settled {
        IMettalexVault mVault = IMettalexVault(mettalexVault);
        mVault.settlePositions();
    }

    function _calcDenormWeights(uint256[3] memory bal, uint256 spotPrice)
        internal
        view
        returns (uint256[3] memory wt)
    {
        //  Number of collateral tokens per pair of long and short tokens
        IMettalexVault mVault = IMettalexVault(mettalexVault);
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
        return wt;
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
        int256 tempDelta;
        uint256 temp;
        address tempAddress;

        if (delta[0] > delta[1]) {
            tempDelta = delta[0];
            delta[0] = delta[1];
            delta[1] = tempDelta;

            temp = balance[0];
            balance[0] = balance[1];
            balance[1] = temp;

            temp = wt[0];
            wt[0] = wt[1];
            wt[1] = temp;

            tempAddress = tokens[0];
            tokens[0] = tokens[1];
            tokens[1] = tempAddress;
        }

        if (delta[1] > delta[2]) {
            tempDelta = delta[1];
            delta[1] = delta[2];
            delta[2] = tempDelta;

            temp = balance[1];
            balance[1] = balance[2];
            balance[2] = temp;

            temp = wt[1];
            wt[1] = wt[2];
            wt[2] = temp;

            tempAddress = tokens[1];
            tokens[1] = tokens[2];
            tokens[2] = tempAddress;
        }

        if (delta[0] > delta[1]) {
            tempDelta = delta[0];
            delta[0] = delta[1];
            delta[1] = tempDelta;

            temp = balance[0];
            balance[0] = balance[1];
            balance[1] = temp;

            temp = wt[0];
            wt[0] = wt[1];
            wt[1] = temp;

            tempAddress = tokens[0];
            tokens[0] = tokens[1];
            tokens[1] = tempAddress;
        }

        IBalancer bPool = IBalancer(balancer);
        bPool.rebind(tokens[0], balance[0], wt[0]);
        bPool.rebind(tokens[1], balance[1], wt[1]);
        bPool.rebind(tokens[2], balance[2], wt[2]);
    }

    function _mintPositions(uint256 _amount) internal {
        IERC20(want).safeApprove(mettalexVault, 0);
        IERC20(want).safeApprove(mettalexVault, _amount);

        IMettalexVault(mettalexVault).mintFromCollateralAmount(_amount);
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

    function _swapFromCoin(
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) internal returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(
            tokenOut == longToken || tokenOut == shortToken,
            "ERR_TOKEN_OUT"
        );

        IBalancer bPool = IBalancer(balancer);
        IERC20(want).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, spotPriceAfter) = bPool.swapExactAmountIn(
            want,
            tokenAmountIn,
            tokenOut,
            1,
            maxPrice
        );

        //Rebalance Pool
        uint256 newSpotPrice = _calculateSpotPrice(OTHER_REBALANCE, 0);
        _rebalance(newSpotPrice);

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(tokenOut).transfer(msg.sender, tokenAmountOut);
    }

    function _swapToCoin(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minAmountOut,
        uint256 maxPrice
    ) internal returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(tokenIn == longToken || tokenIn == shortToken, "ERR_TOKEN_IN");

        IBalancer bPool = IBalancer(balancer);
        IERC20(tokenIn).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, spotPriceAfter) = bPool.swapExactAmountIn(
            tokenIn,
            tokenAmountIn,
            want,
            minAmountOut,
            maxPrice
        );

        //Rebalance Pool
        uint256 newSpotPrice = _calculateSpotPrice(OTHER_REBALANCE, 0);
        _rebalance(newSpotPrice);

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(want).transfer(msg.sender, tokenAmountOut);
    }

    function _swapPositions(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) internal returns (uint256 tokenAmountOut, uint256 spotPriceAfter) {
        require(tokenIn != tokenOut, "ERR_SAME_TOKEN_SWAP");
        require(tokenIn == longToken || tokenIn == shortToken, "ERR_TOKEN_IN");
        require(
            tokenOut == longToken || tokenOut == shortToken,
            "ERR_TOKEN_OUT"
        );

        IBalancer bPool = IBalancer(balancer);
        IERC20(tokenIn).safeApprove(balancer, tokenAmountIn);

        (tokenAmountOut, spotPriceAfter) = bPool.swapExactAmountIn(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            maxPrice
        );

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(tokenOut).transfer(msg.sender, tokenAmountOut);
    }

    // This function should return Total valuation of balancer pool.
    // i.e. ( LTK + STK + Coin ) from balancer pool.
    function _getBalancerPoolValue()
        internal
        view
        returns (uint256 totalValuation)
    {
        uint256 poolStkBalance = IERC20(shortToken).balanceOf(
            address(balancer)
        );
        uint256 poolLtkBalance = IERC20(longToken).balanceOf(address(balancer));

        totalValuation = IERC20(want).balanceOf(address(balancer));
        IBalancer bpool = IBalancer(balancer);

        //get short price values in want
        if (poolStkBalance != 0) {
            uint256 stkSpot = bpool.getSpotPriceSansFee(want, shortToken);
            uint256 totalValueInCoin = (stkSpot.mul(poolStkBalance)).div(1e18);
            totalValuation = totalValuation.add(totalValueInCoin);
        }

        //get long price values in want
        if (poolLtkBalance != 0) {
            uint256 ltkSpot = bpool.getSpotPriceSansFee(want, longToken);
            uint256 totalValueInCoin = (ltkSpot.mul(poolLtkBalance)).div(1e18);
            totalValuation = totalValuation.add(totalValueInCoin);
        }
        return totalValuation;
    }

    function _depositInternal(uint256 spotPrice) private {
        // Get coin token balance and allocate half to minting position tokens
        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );

        //check to prevent revert in case of earn and withdraw from pool
        // balancer limitation for 10**12 tokens
        if (wantBeforeMintandDeposit < 10**12) {
            return;
        }

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
        uint256[3] memory wt = _calcDenormWeights(bal, spotPrice);

        IBalancer bPool = IBalancer(balancer);
        // Rebind tokens to balancer pool again with newly calculated weights
        bool isWantBound = bPool.isBound(want);
        bool isStkBound = bPool.isBound(shortToken);
        bool isLtkBound = bPool.isBound(longToken);

        if (isStkBound != true && isLtkBound != true && isWantBound != true) {
            bPool.bind(shortToken, bal[0], wt[0]);
            bPool.bind(longToken, bal[1], wt[1]);
            bPool.bind(want, bal[2], wt[2]);
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
}
