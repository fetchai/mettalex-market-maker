pragma solidity ^0.5.2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMarketContract.sol";


contract IMintable {
    function mint(address _to, uint256 _value) external;

    function burn(address _from, uint256 _value) external;
}


contract MettalexContract {
    using SafeMath for uint256;

    string public CONTRACT_NAME = "Mettalex";

    uint256 public PRICE_SPOT; // MMcD 20200430: Addition to interface to allow admin to set pricing
    address internal owner;

    // Trade At Settlement: keep track of cumulative tokens on each side
    // and partition settlement amount based on (addedQuantity - initialQuantity)/totalSettled
    struct SettlementOrder {
        uint256 index;
        uint256 initialQuantity;
        uint256 addedQuantity;
    }
    mapping(address => SettlementOrder) internal longToSettle;
    mapping(address => SettlementOrder) internal shortToSettle;

    // State variables that are cleared after each price update
    // These keep track of total long and short trade at settlement orders
    // that have been submitted
    uint256 internal totalLongToSettle;
    uint256 internal totalShortToSettle;

    // Running count of number of price updates
    uint256 internal priceUpdateCount;

    // For each price update we store the total amount of position tokens that have been
    // settled using time at settlement orders, and the proportion of total value that
    // goes to long and short positions.
    mapping(uint256 => uint256) internal totalSettled;
    mapping(uint256 => uint256) internal longSettledValue;
    mapping(uint256 => uint256) internal shortSettledValue;

    uint256 public PRICE_CAP;
    uint256 public PRICE_FLOOR;
    uint256 public QTY_MULTIPLIER; // multiplier corresponding to the value of 1 increment in price to token base units
    uint256 public COLLATERAL_PER_UNIT; // required collateral amount for the full range of outcome tokens
    uint256 public COLLATERAL_TOKEN_FEE_PER_UNIT;
    uint256 public lastPrice;
    uint256 public settlementPrice;
    uint256 public settlementTimeStamp;
    // TO-DO: Check requirement on contract completion
    bool public isSettled = false;

    address public COLLATERAL_TOKEN_ADDRESS;
    address public COLLATERAL_POOL_ADDRESS;
    address public LONG_POSITION_TOKEN;
    address public SHORT_POSITION_TOKEN;
    address public ORACLE_ADDRESS;

    mapping(address => bool) public contractWhitelist;

    event UpdatedLastPrice(uint256 price);
    event ContractSettled(uint256 settlePrice);
    event Redeem(
        address indexed to,
        uint256 burntTokenQuantity,
        uint256 collateralToReturn
    );
    event LongPositionTokenMinted(
        address indexed to,
        uint256 value,
        uint256 collateralRequired,
        uint256 collateralFeeRequired
    );
    event ShortPositionTokenMinted(
        address indexed to,
        uint256 value,
        uint256 collateralRequired,
        uint256 collateralFeeRequired
    );
    event OrderedLongTAS(
        address indexed from,
        uint256 orderIndex,
        uint256 initialTotalLongToSettle,
        uint256 quantityToTrade
    );
    event OrderedShortTAS(
        address indexed from,
        uint256 orderIndex,
        uint256 initialTotalLongToSettle,
        uint256 quantityToTrade
    );
    event ClearedLongSettledTrade(
        address indexed sender,
        uint256 settledValue,
        uint256 senderContribution,
        uint256 senderExcess,
        uint256 positionQuantity,
        uint256 collateralQuantity
    );
    event ClearedShortSettledTrade(
        address indexed sender,
        uint256 settledValue,
        uint256 senderContribution,
        uint256 senderExcess,
        uint256 positionQuantity,
        uint256 collateralQuantity
    );

    constructor(
        address collateralToken,
        address longPositionToken,
        address shortPositionToken,
        address oracleAddress,
        uint256 cap,
        uint256 floor,
        uint256 multiplier,
        uint256 feeRate
    ) public {
        COLLATERAL_POOL_ADDRESS = address(this);
        COLLATERAL_TOKEN_ADDRESS = collateralToken;
        LONG_POSITION_TOKEN = longPositionToken;
        SHORT_POSITION_TOKEN = shortPositionToken;
        ORACLE_ADDRESS = oracleAddress;

        PRICE_CAP = cap;
        PRICE_FLOOR = floor;
        QTY_MULTIPLIER = multiplier;
        COLLATERAL_PER_UNIT = cap.sub(floor).mul(multiplier);
        COLLATERAL_TOKEN_FEE_PER_UNIT = cap
            .add(floor)
            .mul(multiplier)
            .mul(feeRate)
            .div(200000);

        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "OWNER_ONLY");
        _;
    }

    function mintPositionTokens(uint256 quantityToMint) external {
        IMarketContract marketContract = IMarketContract(address(this));
        require(!marketContract.isSettled(), "Contract is already settled");

        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);
        uint256 collateralRequired = COLLATERAL_PER_UNIT.mul(quantityToMint);

        uint256 collateralFeeRequired = COLLATERAL_TOKEN_FEE_PER_UNIT.mul(
            quantityToMint
        );
        collateral.transferFrom(
            msg.sender,
            address(this),
            collateralRequired.add(collateralFeeRequired)
        );

        IMintable long = IMintable(LONG_POSITION_TOKEN);
        IMintable short = IMintable(SHORT_POSITION_TOKEN);
        long.mint(msg.sender, quantityToMint);
        emit LongPositionTokenMinted(
            msg.sender,
            quantityToMint,
            collateralRequired,
            collateralFeeRequired
        );
        short.mint(msg.sender, quantityToMint);
        emit ShortPositionTokenMinted(
            msg.sender,
            quantityToMint,
            collateralRequired,
            collateralFeeRequired
        );
    }

    // MMcD 20200430: New method to trade at settlement price on next spot price update
    function tradeAtSettlement(address token, uint256 quantityToTrade)
        external
    {
        require(
            (token == LONG_POSITION_TOKEN) || (token == SHORT_POSITION_TOKEN),
            "Given address must be either of Long Position Token or Short Position Token"
        );
        IERC20 position = IERC20(token);
        if (token == LONG_POSITION_TOKEN) {
            require(
                longToSettle[msg.sender].addedQuantity == 0,
                "Single TAS order allowed"
            );
            longToSettle[msg.sender] = SettlementOrder({
                index: priceUpdateCount,
                initialQuantity: totalLongToSettle,
                addedQuantity: quantityToTrade
            });
            totalLongToSettle += quantityToTrade;
        } else {
            require(
                shortToSettle[msg.sender].addedQuantity == 0,
                "Single TAS order allowed"
            );
            shortToSettle[msg.sender] = SettlementOrder({
                index: priceUpdateCount,
                initialQuantity: totalShortToSettle,
                addedQuantity: quantityToTrade
            });
            totalShortToSettle += quantityToTrade;
        }
        position.transferFrom(msg.sender, address(this), quantityToTrade);

        if (token == LONG_POSITION_TOKEN) {
            emit OrderedLongTAS(
                msg.sender,
                priceUpdateCount,
                totalLongToSettle - quantityToTrade,
                quantityToTrade
            );
        } else {
            emit OrderedShortTAS(
                msg.sender,
                priceUpdateCount,
                totalLongToSettle - quantityToTrade,
                quantityToTrade
            );
        }
    }

    function clearLongSettledTrade() external {
        _clearSettledTrade(
            longToSettle[msg.sender].index,
            longToSettle[msg.sender].initialQuantity,
            longToSettle[msg.sender].addedQuantity,
            longSettledValue[longToSettle[msg.sender].index],
            LONG_POSITION_TOKEN
        );
    }

    function clearShortSettledTrade() external {
        _clearSettledTrade(
            shortToSettle[msg.sender].index,
            shortToSettle[msg.sender].initialQuantity,
            shortToSettle[msg.sender].addedQuantity,
            shortSettledValue[shortToSettle[msg.sender].index],
            SHORT_POSITION_TOKEN
        );
    }

    function updateSpot(uint256 price) external {
        require(msg.sender == ORACLE_ADDRESS, "ORACLE_ONLY");
        require(
            price >= PRICE_FLOOR && price <= PRICE_CAP,
            "arbitration price must be within contract bounds"
        );
        PRICE_SPOT = price;
        // Deal with trade at settlement orders
        // For each settlement event we store the total amount of position tokens crossed
        // and the total value of the long and short positions
        if ((totalLongToSettle > 0) && (totalShortToSettle > 0)) {
            uint256 settled = 0;
            if (totalLongToSettle >= totalShortToSettle) {
                settled = totalShortToSettle;
            } else {
                settled = totalLongToSettle;
            }
            // Clear per period variables that track running total
            totalLongToSettle = 0;
            totalShortToSettle = 0;
            // Store position tokens settled amount and value going to long and short position
            longSettledValue[priceUpdateCount] = PRICE_SPOT
                .sub(PRICE_FLOOR)
                .mul(settled)
                .div(PRICE_CAP.sub(PRICE_FLOOR));
            shortSettledValue[priceUpdateCount] = PRICE_CAP
                .sub(PRICE_SPOT)
                .mul(settled)
                .div(PRICE_CAP.sub(PRICE_FLOOR));
            totalSettled[priceUpdateCount] = settled;

            priceUpdateCount += 1;

            // Burn crossed tokens.  Backing collateral is held in this contract
            // in the totalSettledValue[ind], longSettledValue[ind], shortSettledValue[ind]
            // state variables
            IMintable long = IMintable(LONG_POSITION_TOKEN);
            IMintable short = IMintable(SHORT_POSITION_TOKEN);
            long.burn(address(this), settled);
            short.burn(address(this), settled);
        }
        emit UpdatedLastPrice(price);
    }

    function settleContract(uint256 finalSettlementPrice) external onlyOwner {
        revert("NOT_IMPLEMENTED");
        //        settlementTimeStamp = now;
        //        settlementPrice = finalSettlementPrice;
        //        emit ContractSettled(finalSettlementPrice);
    }

    function arbitrateSettlement(uint256 price) external onlyOwner {
        revert("NOT_IMPLEMENTED");
        //        require(price >= PRICE_FLOOR && price <= PRICE_CAP, "arbitration price must be within contract bounds");
        //        lastPrice = price;
        //        emit UpdatedLastPrice(price);
        //        settleContract(price);
        //        isSettled = true;
    }

    function settleAndClose(
        address,
        uint256,
        uint256
    ) external onlyOwner {
        revert("NOT_IMPLEMENTED");
    }

    function addAddressToWhiteList(address contractAddress) external onlyOwner {
        contractWhitelist[contractAddress] = true;
    }

    function priceUpdater() external view returns (address) {
        return ORACLE_ADDRESS;
    }

    function redeemPositionTokens(
        address to_address, // Destination address for collateral redeemed
        uint256 quantityToRedeem
    ) public {
        IMintable long = IMintable(LONG_POSITION_TOKEN);
        IMintable short = IMintable(SHORT_POSITION_TOKEN);

        long.burn(msg.sender, quantityToRedeem);
        short.burn(msg.sender, quantityToRedeem);

        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);
        uint256 collateralToReturn = COLLATERAL_PER_UNIT.mul(quantityToRedeem);
        // Destination address may not be the same as sender e.g. send to
        // exchange wallet receive funds address
        collateral.transfer(to_address, collateralToReturn);
        emit Redeem(to_address, quantityToRedeem, collateralToReturn);
    }

    // Overloaded method to redeem collateral to sender address
    function redeemPositionTokens(uint256 quantityToRedeem) public {
        redeemPositionTokens(msg.sender, quantityToRedeem);
    }

    function _clearSettledTrade(
        uint256 settleIndex,
        uint256 initialQuantity,
        uint256 addedQuantity,
        uint256 settledValue,
        address positionTokenType
    ) private {
        // Post TAS retrieve the collateral from settlement
        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);

        if (addedQuantity > 0) {
            require(
                settleIndex < priceUpdateCount,
                "Can only clear previously settled order"
            );
            uint256 contribution = addedQuantity;
            uint256 excessQuantity = 0;
            if ((contribution + initialQuantity) >= totalSettled[settleIndex]) {
                // Cap the amount of collateral that can be reclaimed to the total
                // settled in TAS auction
                if (initialQuantity >= totalSettled[settleIndex]) {
                    contribution = 0;
                } else {
                    contribution = totalSettled[settleIndex] - initialQuantity;
                }
                // Transfer any uncrossed position tokens
                excessQuantity = addedQuantity - contribution;
            }

            if (positionTokenType == LONG_POSITION_TOKEN) {
                longToSettle[msg.sender].index = 0;
                longToSettle[msg.sender].addedQuantity = 0;
                longToSettle[msg.sender].initialQuantity = 0;
            } else {
                shortToSettle[msg.sender].index = 0;
                shortToSettle[msg.sender].addedQuantity = 0;
                shortToSettle[msg.sender].initialQuantity = 0;
            }

            uint256 positionQuantity = contribution.mul(settledValue).div(
                totalSettled[settleIndex]
            );
            uint256 collateralQuantity = COLLATERAL_PER_UNIT.mul(
                positionQuantity
            );

            // Transfer any uncrossed position tokens
            IERC20 token = IERC20(positionTokenType);
            token.transfer(msg.sender, excessQuantity);
            // Transfer reclaimed collateral
            collateral.transfer(msg.sender, collateralQuantity);

            if (positionTokenType == LONG_POSITION_TOKEN) {
                emit ClearedLongSettledTrade(
                    msg.sender,
                    settledValue,
                    contribution,
                    excessQuantity,
                    positionQuantity,
                    collateralQuantity
                );
            } else {
                emit ClearedShortSettledTrade(
                    msg.sender,
                    settledValue,
                    contribution,
                    excessQuantity,
                    positionQuantity,
                    collateralQuantity
                );
            }
        }
    }
}
