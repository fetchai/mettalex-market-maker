pragma solidity ^0.5.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IBalancer.sol";
import "../interfaces/IMettalexVault.sol";
import "../interfaces/IYController.sol";
import "../interfaces/IStrategyHelper.sol";

/**
 * @title StrategyBalancerMettalexV3
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
contract StrategyBalancerMettalexV3 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    uint256 private constant APPROX_MULTIPLIER = 47;
    uint256 private constant INITIAL_MULTIPLIER = 50;
    uint256 public minMtlxBalance;
    uint256 public constant MAX_DIST_FEE = 10**18;
    uint256 public distFee = 0;
    uint256 public exitFee = 0;
    uint256 public MAX_EXIT_FEE = 10**18;

    address public want;
    address public balancer;
    address public mettalexVault;
    address public longToken;
    address public shortToken;
    address public governance;
    address public mtlxToken;
    address public controller;
    address public newStrategy;
    address public distributionContract;
    address public strategyHelper;

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
        address _shortToken,
        address _mtlxToken
    ) public {
        want = _want;
        balancer = _balancer;
        mettalexVault = _mettalexVault;
        longToken = _longToken;
        shortToken = _shortToken;
        mtlxToken = _mtlxToken;
        governance = msg.sender;
        controller = _controller;
        breaker = false;
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
     * @dev Throws if MTLX balance is less than minMtlxBalance
     */
    modifier hasMTLX {
        require(
            IERC20(mtlxToken).balanceOf(msg.sender) >= minMtlxBalance,
            "ERR_MIN_MTLX_BALANCE"
        );
        _;
    }

    /**
     * @dev Used to deposit and bind/rebalance the balancer pool
     * @dev Can be called by controller only
     */
    function deposit() external notSettled {
        require(msg.sender == controller, "!controller");
        require(!breaker, "!breaker");

        _depositInternal();
    }

    /**
     * @dev Used to withdraw partial funds, normally used with a vault withdrawal
     * @dev Can be called by controller only
     * @param _amount uint256 The amount of want to withdraw
     */
    function withdraw(uint256 _amount) external {
        // check if breached: return
        require(msg.sender == controller, "!controller");
        require(!breaker, "!breaker");

        IMettalexVault mVault = IMettalexVault(mettalexVault);
        if (mVault.isSettled()) {
            handleBreach();
            IERC20(want).safeTransfer(
                IYController(controller).vaults(want),
                _amount
            );
        } else {
            _unbind();

            _redeemPositions();

            uint256 fees = _amount.mul(exitFee).div(MAX_EXIT_FEE);
            _amount = _amount.sub(fees);

            // Transfer out required funds to yVault.
            IERC20(want).safeTransfer(
                IYController(controller).vaults(want),
                _amount
            );

            _depositInternal();
        }
    }

    /**
     * @dev Used for creating additional rewards from dust
     * @dev Can be called by controller only
     * @param _token address The address of token to collect
     * @return The balance of this contract for given token address
     */
    function withdraw(address _token) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(!breaker, "!breaker");
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

        require(newStrategy != address(0), "!strategy");
        if (ltkDust != 0) IERC20(longToken).safeTransfer(newStrategy, ltkDust);
        if (stkDust != 0) IERC20(shortToken).safeTransfer(newStrategy, stkDust);
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
    )
        external
        hasMTLX
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(tokenAmountIn > 0, "ERR_AMOUNT_IN");

        //get tokens
        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            tokenAmountIn
        );

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
    function updateSpotAndNormalizeWeights() public notSettled {
        _rebalance(IMettalexVault(mettalexVault).priceSpot());
    }

    /**
     * @dev Used to settle all Long and Short tokens held by the contract
     * in case of Commodity breach
     * @dev Should be called only once (before updating commodity addresses)
     * @dev isBreachHandled updated in updateCommodityAfterBreach() with same BPool and Strategy
     * but new position tokens and vault
     */
    function handleBreach() public settled {
        require(!breaker, "!breaker");
        if (!isBreachHandled) {
            isBreachHandled = true;
            // Unbind tokens from Balancer pool
            _unbind();
            _settle();
        }
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

        _depositInternal();

        isBreachHandled = false;
    }

    /**
     * @dev Used to get balance of strategy in terms of want
     * @dev Gets pool value (LTK + STK + USDT (want)) in terms of USDT and
     * adds the amount to this contract balance.
     * @return The balance of strategy and bpool in terms of want
     */
    function balanceOf() external view returns (uint256 total) {
        //Balance of strategy
        (uint256 stkPrice, uint256 ltkPrice) = _getSpotPrice();

        uint256 stkBalance = IERC20(shortToken).balanceOf(address(this)).mul(
            stkPrice
        );
        uint256 ltkBalance = IERC20(longToken).balanceOf(address(this)).mul(
            ltkPrice
        );

        total = IERC20(want).balanceOf(address(this)).add(stkBalance).add(
            ltkBalance
        );

        //balance of BPool
        total = _getBalancerPoolValue().add(total);
    }

    /**
     * @dev Used to update governance address
     * @dev Can be called by governance only
     * @param _governance address The address of new governance
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        require(
            (_governance != address(0)) && (_governance != address(this)),
            "invalid governance address"
        );
        governance = _governance;
    }

    /**
     * @dev Used to update min required MTLX balance
     * @dev Can be called by governance only
     * @param balance The new minMtlxBalance required
     */
    function setMinMtlxBalance(uint256 balance) external {
        require(msg.sender == governance, "!governance");
        minMtlxBalance = balance;
    }

    /**
     * @dev Used to update MTLX address
     * @dev Can be called by governance only
     * @param _mtlxToken address The address of new MTLX token
     */
    function setMtlxTokenAddress(address _mtlxToken) external {
        require(msg.sender == governance, "!governance");
        require((_mtlxToken != address(0)), "invalid token address");
        mtlxToken = _mtlxToken;
    }

    /**
     * @dev Used to update new strategy address
     * @dev Can be called by governance only
     * @param _strategy address The address of new strategy
     */
    function setNewStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        require((_strategy != address(0)), "invalid New Strategy");
        newStrategy = _strategy;
    }

    /**
     * @dev Used to update controller for strategy
     * @dev Can be called by governance only
     * @param _controller address The address of new controller
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        require(
            (_controller != address(0)) && (_controller != address(this)),
            "invalid controller address"
        );
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
     * @dev Used to update dist fee
     * @dev Can be called by governance only
     * @param _distFee uint256 The new swap fee
     */
    function setDistFee(uint256 _distFee) external {
        require(msg.sender == governance, "!governance");
        require(_distFee < MAX_DIST_FEE, "MAX_DIST_FEE");
        distFee = _distFee;
    }

    /**
     * @dev Used to update exit fee
     * @dev Can be called by governance only
     * @param _exitFee uint256 The new exit fee
     */
    function setExitFee(uint256 _exitFee) external {
        require(msg.sender == governance, "!governance");
        require(_exitFee < MAX_EXIT_FEE, "MAX_EXIT_FEE");
        exitFee = _exitFee;
    }

    /**
     * @dev Used to update new distributionContract address
     * @dev Can be called by governance only
     * @param _distributionContract address The address of new strategy
     */
    function setDistributionContract(address _distributionContract) external {
        require(msg.sender == governance, "!governance");
        require((_distributionContract != address(0)), "invalid New distributionContract");
        distributionContract = _distributionContract;
    }

    function setStrategyHelper(address _strategyHelper) external {
        require(msg.sender == governance, "!governance");
        require((_strategyHelper != address(0)), "invalid strategyHelper");
        strategyHelper = _strategyHelper;
    }
    /**
     * @dev Used to update new distributionContract address
     * @dev Can be called by governance only
     * @param _distributionContract address The address of new distribution contract
     * @param _distributionFee The new distribution fee
     */
    function setDistribution(address _distributionContract, uint256 _distributionFee) external {
        require(msg.sender == governance, "!governance");
        require((_distributionContract != address(0)), "invalid New distributionContract");
        require((_distributionFee < MAX_DIST_FEE), "MAX_DIST_FEE");
        distributionContract = _distributionContract;
        distFee = _distributionFee;
    }


    /**
     * @dev Used to pause the contract functions on which break is applied
     * @dev Can be called by governance only
     * @param _breaker bool The boolean value indicating contract is paused or not
     */
    function setBreaker(bool _breaker) external {
        require(msg.sender == governance, "!governance");
        breaker = _breaker;
    }

    /**
     * @dev Used to update balancer pool controller address
     * @dev Can be called by governance only
     * @param _controller address The address of new controller
     */
    function updatePoolController(address _controller) external {
        require(msg.sender == governance, "!governance");
        require(
            (_controller != address(0)) && (_controller != address(this)),
            "invalid controller address"
        );

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
    function isBound(address token) public view returns (bool) {
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
    ) external view returns (uint256 tokensReturned, uint256 priceImpact) {
        IBalancer bpool = IBalancer(balancer);

        require(bpool.isBound(fromToken));
        require(bpool.isBound(toToken));
        uint256 swapFee = bpool.getSwapFee();
        uint256 fee = swapFee.add(distFee);

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
            fee
        );

        if (tokensReturned == 0) return (tokensReturned, 0);

        uint256 spotPrice = bpool.getSpotPrice(fromToken, toToken);

        uint256 effectivePrice = (fromTokenAmount.mul(1 ether)).div(
            tokensReturned
        );
        priceImpact = ((effectivePrice.sub(spotPrice)).mul(1 ether)).div(
            spotPrice
        );
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
        uint256 fee = swapFee.add(distFee);

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
            fee
        );

        if (tokensReturned == 0) return (tokensReturned, 0);

        uint256 spotPrice = bpool.getSpotPrice(fromToken, toToken);
        uint256 effectivePrice = (tokensReturned.mul(1 ether)).div(
            toTokenAmount
        );
        priceImpact = ((effectivePrice.sub(spotPrice)).mul(1 ether)).div(
            spotPrice
        );
    }

    function _calculateSpotPrice() internal view returns (uint256 spotPrice) {
        IMettalexVault mVault = IMettalexVault(mettalexVault);
        uint256 floor = mVault.priceFloor();
        uint256 cap = mVault.priceCap();

        //get spot price from balancer pool
        IBalancer bPool = IBalancer(balancer);

        if (!bPool.isBound(want)) {
            spotPrice = mVault.priceSpot();
            return spotPrice;
        }

        uint256 priceShort = bPool.getSpotPrice(want, shortToken);
        uint256 priceLong = bPool.getSpotPrice(want, longToken);

        spotPrice = floor.add(
            (cap.sub(floor)).mul(priceLong).div(priceShort.add(priceLong))
        );
    }

    /**
     * @dev Used to get spot price of positions
     * @dev If Bpool is not active then prices will be:
     * long price: CPU*(spot-floor)/(cap-floor)
     * short price: CPU*(cap-spot)/(cap-floor)
     * @return price of long and short tokens in terms of want
     */
    function _getSpotPrice()
        internal
        view
        returns (uint256 shortPrice, uint256 longPrice)
    {
        if (isBound(want)) {
            shortPrice = IBalancer(balancer).getSpotPrice(want, shortToken);
            longPrice = IBalancer(balancer).getSpotPrice(want, longToken);
        } else {
            uint256 collateralPerUnit = IMettalexVault(mettalexVault)
                .collateralPerUnit();
            uint256 cap = IMettalexVault(mettalexVault).priceCap();
            uint256 floor = IMettalexVault(mettalexVault).priceFloor();
            uint256 spot = IMettalexVault(mettalexVault).priceSpot();

            shortPrice = collateralPerUnit.mul(
                (spot.sub(floor)).div(cap.sub(floor))
            );
            longPrice = collateralPerUnit.mul(
                (cap.sub(spot)).div(cap.sub(floor))
            );
        }
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

    function _rebalance(uint256 spotPrice) internal {
        // Get AMM Pool token balances
        uint256[3] memory bal;
        bal[0] = IERC20(shortToken).balanceOf(balancer);
        bal[1] = IERC20(longToken).balanceOf(balancer);
        bal[2] = IERC20(want).balanceOf(balancer);

        // Re-calculate de-normalised weights
        uint256[3] memory newWt = IStrategyHelper(strategyHelper).CalcDenormWeights(bal, spotPrice, mettalexVault);

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
        if (delta[0] > delta[1]) {
            (delta[0], delta[1]) = (delta[1], delta[0]);
            (balance[0], balance[1]) = (balance[1], balance[0]);
            (wt[0], wt[1]) = (wt[1], wt[0]);
            (tokens[0], tokens[1]) = (tokens[1], tokens[0]);
        }

        if (delta[1] > delta[2]) {
            (delta[1], delta[2]) = (delta[2], delta[1]);
            (balance[1], balance[2]) = (balance[2], balance[1]);
            (wt[1], wt[2]) = (wt[2], wt[1]);
            (tokens[1], tokens[2]) = (tokens[2], tokens[1]);
        }

        if (delta[0] > delta[1]) {
            (delta[0], delta[1]) = (delta[1], delta[0]);
            (balance[0], balance[1]) = (balance[1], balance[0]);
            (wt[0], wt[1]) = (wt[1], wt[0]);
            (tokens[0], tokens[1]) = (tokens[1], tokens[0]);
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
        _unbind();
        _redeemPositions();
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
        uint256 distAmount = distFee.mul(tokenAmountIn).div(MAX_DIST_FEE);
        if ((distAmount != 0) && (distributionContract != address(0))) {
            IERC20(want).safeTransferFrom(msg.sender, address(this), distAmount);
            IERC20(want).safeTransfer(distributionContract, distAmount);
        }
        uint256 swapAmount = tokenAmountIn.sub(distAmount);
        IERC20(want).safeApprove(balancer, swapAmount);

        (tokenAmountOut, spotPriceAfter) = bPool.swapExactAmountIn(
            want,
            swapAmount,
            tokenOut,
            1,
            maxPrice
        );

        //Rebalance Pool
        updateSpotAndNormalizeWeights();

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        IERC20(tokenOut).safeTransfer(msg.sender, tokenAmountOut);
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
        updateSpotAndNormalizeWeights();

        uint256 distAmount = distFee.mul(tokenAmountOut).div(MAX_DIST_FEE);
        uint256 returnAmount = tokenAmountOut.sub(distAmount);

        require(tokenAmountOut >= minAmountOut, "ERR_MIN_OUT");
        if((distributionContract != address(0)) && (distAmount != 0)){
            IERC20(want).safeTransfer(distributionContract, distAmount);
        }
        IERC20(want).safeTransfer(msg.sender, returnAmount);
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
        IERC20(tokenOut).safeTransfer(msg.sender, tokenAmountOut);
    }

    // This function should return Total valuation of balancer pool.
    // i.e. ( LTK + STK + Coin ) from balancer pool.
    function _getBalancerPoolValue()
        internal
        view
        returns (uint256 totalValuation)
    {
        if (!isBound(want)) return 0;

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

    function _depositInternal() private {
        // Get coin token balance and allocate half to minting position tokens
        uint256 wantBeforeMintandDeposit = IERC20(want).balanceOf(
            address(this)
        );
        uint256 wantToVault = wantBeforeMintandDeposit.div(2);

        uint256 positionsExpected = wantToVault.div(
            IMettalexVault(mettalexVault).collateralPerUnit()
        );

        // Get AMM Pool token balances
        uint256 balancerWant = IERC20(want).balanceOf(balancer);
        uint256 balancerLtk = IERC20(longToken).balanceOf(balancer);
        uint256 balancerStk = IERC20(shortToken).balanceOf(balancer);

        // Get strategy balance
        uint256 strategyLtk = IERC20(longToken).balanceOf(address(this));
        uint256 strategyStk = IERC20(shortToken).balanceOf(address(this));

        //Bpool limitation for binding token
        if (
            balancerLtk.add(positionsExpected).add(strategyLtk) < 10**6 ||
            balancerStk.add(positionsExpected).add(strategyStk) < 10**6
        ) {
            return;
        }

        _mintPositions(wantToVault);

        // Get Strategy token balances
        uint256 strategyWant = IERC20(want).balanceOf(address(this));
        strategyLtk = IERC20(longToken).balanceOf(address(this));
        strategyStk = IERC20(shortToken).balanceOf(address(this));

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
        uint256[3] memory wt = IStrategyHelper(strategyHelper).CalcDenormWeights(
            bal,
            IMettalexVault(mettalexVault).priceSpot(),
            mettalexVault
        );

        IBalancer bPool = IBalancer(balancer);
        // Rebind tokens to balancer pool again with newly calculated weights
        bool isWantBound = bPool.isBound(want);
        bool isStkBound = bPool.isBound(shortToken);
        bool isLtkBound = bPool.isBound(longToken);

        if (!isStkBound && !isLtkBound && !isWantBound) {
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