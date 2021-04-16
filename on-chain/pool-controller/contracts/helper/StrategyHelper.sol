pragma solidity ^0.5.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IMettalexVault.sol";
import "../interfaces/IYController.sol";
// import "../interfaces/IFeeDistributor.sol";

contract StrategyHelper {
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

    uint256 private constant APPROX_MULTIPLIER = 47;
    uint256 private constant INITIAL_MULTIPLIER = 50;

    function CalcDenormWeights(uint256[3] memory bal, uint256 spotPrice, address mettalexVault)
        public
        view
        returns (uint256[3] memory wt)
    {
        //  Number of collateral tokens per pair of long and short tokens
        IMettalexVault mVault = IMettalexVault(mettalexVault);
        PriceInfo memory price;

        price.spot = spotPrice; //mVault.priceSpot();
        price.floor = mVault.priceFloor();
        price.cap = mVault.priceCap();
        price.range = price.cap.sub(price.floor);
        price.C = mVault.collateralPerUnit();

        // Try to 'avoid CompilerError: Stack too deep, try removing local variables.'
        // by using single variable to store [x_s, x_l, x_c]

        //--------------------------------------------
        //bal[0] = x_s
        //price.C = C
        //(price.spot.sub(price.floor)).div(price.range) = v
        //(price.cap.sub(price.spot)).div(price.range) = 1-v
        //bal[1] = x_l
        //bal[2] = x_c
        //-------------------------------------------

        //-x_c*(v*(x_l - x_s) - x_l)
        price.dc = (
            bal[2].mul((price.spot.sub(price.floor))).mul(bal[0]).div(
                price.range
            )
        );
        price.dc = price.dc.add(bal[2].mul(bal[1])).sub(
            bal[2].mul((price.spot.sub(price.floor))).mul(bal[1]).div(
                price.range
            )
        );

        //C*v*x_l*x_s
        price.dl = (price.C)
            .mul(bal[1])
            .mul(bal[0])
            .mul((price.spot.sub(price.floor)))
            .div(price.range);

        //C*x_l*x_s*(1-v)
        price.ds = price
            .C
            .mul(bal[1])
            .mul(bal[0])
            .mul((price.cap.sub(price.spot)))
            .div(price.range);

        //C*x_l*x_s + x_c*((v*x_s) + (1-v)*x_l)
        price.d = price.dc.add(price.dl).add(price.ds);

        wt[0] = price.ds.mul(1 ether).div(price.d);
        wt[1] = price.dl.mul(1 ether).div(price.d);
        wt[2] = price.dc.mul(1 ether).div(price.d);

        // current price at +-1% of floor or cap
        uint256 x = price.range.div(100);

        //adjusting weights to avoid max and min weight errors in BPool
        if (
            price.floor.add(x) >= price.spot || price.cap.sub(x) <= price.spot
        ) {
            wt[0] = wt[0].mul(APPROX_MULTIPLIER).add(1 ether);
            wt[1] = wt[1].mul(APPROX_MULTIPLIER).add(1 ether);
            wt[2] = wt[2].mul(APPROX_MULTIPLIER).add(1 ether);
        } else {
            wt[0] = wt[0].mul(INITIAL_MULTIPLIER);
            wt[1] = wt[1].mul(INITIAL_MULTIPLIER);
            wt[2] = wt[2].mul(INITIAL_MULTIPLIER);
        }

        return wt;
    }
}