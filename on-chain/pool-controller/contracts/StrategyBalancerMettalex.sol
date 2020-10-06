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

contract StrategyBalancerMettalex {
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

    // OpenZeppelin SDK upgradeable contract
    bool private initialized;

    modifier notSettled {
        MettalexVault mVault = MettalexVault(mettalex_vault);
        require(!mVault.isSettled(), "mVault is already settled");
        _;
    }

    modifier settled {
        MettalexVault mVault = MettalexVault(mettalex_vault);
        require(mVault.isSettled(), "mVault should be settled");
        _;
    }

    modifier callOnce {
        if (!isBreachHandled) {
            _;
        }
    }

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

    function settle() internal settled {
        MettalexVault mVault = MettalexVault(mettalex_vault);
        mVault.settlePositions();
    }

    // Settle all Long and Short tokens held by the contract in case of Commodity breach
    // should be called only once
    function handleBreach() public settled callOnce {
        // TO-DO: Understand requirement and remove/keep this check
        require(breaker == false, "!breaker");

        isBreachHandled = true;

        Balancer bPool = Balancer(balancer);

        // Set public swap to false
        bPool.setPublicSwap(false);

        // Unbind tokens from Balancer pool
        unbind();
        settle();
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
        view
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
        uint256[3] memory newWt = calcDenormWeights(bal);

        address[3] memory tokens = [short_token, long_token, want];

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

        sortAndRebind(delta, newWt, bal, tokens);
    }

    function sortAndRebind(
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
        require(breaker == false, "!breaker");
        Balancer bPool = Balancer(balancer);

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

        MettalexVault(mettalex_vault).mintFromCollateralAmount(wantToVault);

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
        uint256[3] memory wt = calcDenormWeights(bal);

        Balancer bPool = Balancer(balancer);
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

            sortAndRebind(delta, wt, bal, tokens);
        }
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        // check if breached: return
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");

        MettalexVault mVault = MettalexVault(mettalex_vault);
        if (mVault.isSettled()) {
            handleBreach();
            IERC20(want).transfer(Controller(controller).vaults(want), _amount);
        } else {
            Balancer bPool = Balancer(balancer);

            // Unbind tokens from Balancer pool
            bPool.setPublicSwap(false);

            unbind();

            redeemPositions();

            // Transfer out required funds to yVault.
            IERC20(want).transfer(Controller(controller).vaults(want), _amount);

            _depositInternal();

            bPool.setPublicSwap(true);
        }

        supply = supply.sub(_amount);
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(address _token) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(breaker == false, "!breaker");
        require(want != address(_token), "want");

        balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(controller, balance);
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
        Balancer bPool = Balancer(balancer);
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
        uint256 collateralPerUnit = MettalexVault(mettalex_vault)
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
        require(Balancer(bPoolAddress).isBound(fromToken));
        require(Balancer(bPoolAddress).isBound(toToken));
        uint256 swapFee = Balancer(bPoolAddress).getSwapFee();

        uint256 tokenBalanceIn = Balancer(bPoolAddress).getBalance(fromToken);
        uint256 tokenBalanceOut = Balancer(bPoolAddress).getBalance(toToken);

        uint256 tokenWeightIn = Balancer(bPoolAddress).getDenormalizedWeight(
            fromToken
        );
        uint256 tokenWeightOut = Balancer(bPoolAddress).getDenormalizedWeight(
            toToken
        );

        tokensReturned = Balancer(bPoolAddress).calcOutGivenIn(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            fromTokenAmount,
            swapFee
        );

        uint256 spotPrice = Balancer(bPoolAddress).getSpotPrice(
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
        require(Balancer(bPoolAddress).isBound(fromToken));
        require(Balancer(bPoolAddress).isBound(toToken));
        uint256 swapFee = Balancer(bPoolAddress).getSwapFee();

        uint256 tokenBalanceIn = Balancer(bPoolAddress).getBalance(fromToken);
        uint256 tokenBalanceOut = Balancer(bPoolAddress).getBalance(toToken);

        uint256 tokenWeightIn = Balancer(bPoolAddress).getDenormalizedWeight(
            fromToken
        );
        uint256 tokenWeightOut = Balancer(bPoolAddress).getDenormalizedWeight(
            toToken
        );

        tokensReturned = Balancer(bPoolAddress).calcInGivenOut(
            tokenBalanceIn,
            tokenWeightIn,
            tokenBalanceOut,
            tokenWeightOut,
            toTokenAmount,
            swapFee
        );

        uint256 spotPrice = Balancer(bPoolAddress).getSpotPrice(
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
