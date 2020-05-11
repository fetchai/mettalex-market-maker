pragma solidity ^0.5.2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMarketContract.sol";

contract IMintable {
    function mint(address _to, uint _value) external;
    function burn(address _from, uint _value) external;
}

contract MettalexContract {
    using SafeMath for uint256;

    string public CONTRACT_NAME = "Mettalex";

    uint public PRICE_SPOT;  // MMcD 20200430: Addition to interface to allow admin to set pricing
    address owner;

    // Trade At Settlement: keep track of cumulative tokens on each side
    // and partition settlement amount based on (addedQty - initialQty)/totalSettled
    struct SettlementOrder {
        uint initialQty;
        uint addedQty;
    }
    mapping (address => SettlementOrder) longToSettle;
    mapping (address => SettlementOrder) shortToSettle;
    uint totalLongToSettle;
    uint totalShortToSettle;
    uint totalSettled;
    // Partition total settled value between long and short positions
    uint longSettledValue;
    uint shortSettledValue;

    uint public PRICE_CAP;
    uint public PRICE_FLOOR;
    uint public PRICE_DECIMAL_PLACES;   // how to convert the pricing from decimal format (if valid) to integer
    uint public QTY_MULTIPLIER;         // multiplier corresponding to the value of 1 increment in price to token base units
    uint public COLLATERAL_PER_UNIT;    // required collateral amount for the full range of outcome tokens
    uint public COLLATERAL_TOKEN_FEE_PER_UNIT;
    uint public MKT_TOKEN_FEE_PER_UNIT;
    uint public EXPIRATION = block.timestamp + 30 days;
    uint public SETTLEMENT_DELAY = 1 days;
    uint public lastPrice;
    uint public settlementPrice;
    uint public settlementTimeStamp;
    bool public isSettled = false;

    address public COLLATERAL_TOKEN_ADDRESS;
    address public COLLATERAL_POOL_ADDRESS;
    address public LONG_POSITION_TOKEN;
    address public SHORT_POSITION_TOKEN;
    address public PRICE_UPDATE_ADDRESS;

    mapping (address => bool) public contractWhitelist;

    event Mint(address indexed to, uint value);
    event Redeem(address indexed to, uint value);
    event UpdatedLastPrice(uint256 price);
    event ContractSettled(uint settlePrice);

    constructor(
        address collateralToken,
        address longPositionToken,
        address shortPositionToken,
        address priceUpdateAddress,
        uint cap,
        uint floor,
        uint multiplier,
        uint feeRate
    )
        public
    {
        COLLATERAL_POOL_ADDRESS = address(this);
        COLLATERAL_TOKEN_ADDRESS = collateralToken;
        LONG_POSITION_TOKEN = longPositionToken;
        SHORT_POSITION_TOKEN = shortPositionToken;
        PRICE_UPDATE_ADDRESS = priceUpdateAddress;

        PRICE_CAP = cap;
        PRICE_FLOOR = floor;
        QTY_MULTIPLIER = multiplier;
        COLLATERAL_PER_UNIT = cap.
            sub(floor).
            mul(multiplier);
        COLLATERAL_TOKEN_FEE_PER_UNIT = cap.
            add(floor).
            div(2).
            mul(multiplier).
            mul(feeRate).
            div(100000);

        MKT_TOKEN_FEE_PER_UNIT = COLLATERAL_TOKEN_FEE_PER_UNIT.
            div(2);
        owner = msg.sender;
    }

    function priceUpdater()
        public
        view
        returns (address)
    {
        return PRICE_UPDATE_ADDRESS;
    }

    function isPostSettlementDelay()
        public
        view
        returns (bool)
    {
        return isSettled && (now >= (settlementTimeStamp + SETTLEMENT_DELAY));
    }

    function mintPositionTokens(
        address marketContractAddress,
        uint qtyToMint,
        bool // Unused, to remove - used to be payFeeInMkt
    )
        external
    {
        IMarketContract marketContract = IMarketContract(marketContractAddress);
        require(!marketContract.isSettled(), "Contract is already settled");

        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);
        uint collateralRequired = COLLATERAL_PER_UNIT.mul(qtyToMint);

        uint collateralFeeRequired = COLLATERAL_TOKEN_FEE_PER_UNIT.mul(qtyToMint);
        collateral.transferFrom(
            msg.sender,
            address(this),
            collateralRequired.add(collateralFeeRequired)
        );

        IMintable long = IMintable(LONG_POSITION_TOKEN);
        IMintable short = IMintable(SHORT_POSITION_TOKEN);
        long.mint(msg.sender, qtyToMint);
        short.mint(msg.sender, qtyToMint);
    }

    function redeemPositionTokens(
        address to_address,
        uint qtyToRedeem
    )
        public
    {
        IMintable long = IMintable(LONG_POSITION_TOKEN);
        IMintable short = IMintable(SHORT_POSITION_TOKEN);

        long.burn(msg.sender, qtyToRedeem);
        short.burn(msg.sender, qtyToRedeem);

        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);
        uint collateralToReturn = COLLATERAL_PER_UNIT.mul(qtyToRedeem);
        collateral.transfer(msg.sender, collateralToReturn);
    }

    // MMcD 20200430: New method to trade at settlement price on next spot price update
    function tradeAtSettlement(
        address token,
        uint qtyToTrade
    )
        public
    {
        require((token == LONG_POSITION_TOKEN) || (token == SHORT_POSITION_TOKEN));
        IERC20 position = IERC20(token);
        if (token == LONG_POSITION_TOKEN) {
            require(longToSettle[msg.sender].addedQty == 0, "Single TAS order allowed" );
            longToSettle[msg.sender] = SettlementOrder(
                {initialQty: totalLongToSettle, addedQty: qtyToTrade}
            );
            totalLongToSettle += qtyToTrade;
        } else {
            require(shortToSettle[msg.sender].addedQty == 0, "Single TAS order allowed" );
            shortToSettle[msg.sender] = SettlementOrder(
                {initialQty: totalShortToSettle, addedQty: qtyToTrade}
            );
            totalShortToSettle += qtyToTrade;
        }
        position.transferFrom(msg.sender, address(this), qtyToTrade);
    }

    function clearLongSettledTrade()
        external
    {
        // 20200430 MMcD: Post TAS retrieve the collateral from settlement
        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);

        if ((longToSettle[msg.sender].addedQty > 0) &&
            (longToSettle[msg.sender].initialQty < totalSettled)
        ) {
            uint contrib = longToSettle[msg.sender].addedQty;
            uint excessQty = 0;
            if ((contrib + longToSettle[msg.sender].initialQty) > totalSettled) {
                // Cap the amount of collateral that can be reclaimed to the total
                // settled in TAS auction
                contrib = totalSettled - longToSettle[msg.sender].initialQty;
                // Transfer any uncrossed position tokens
                excessQty = longToSettle[msg.sender].addedQty - contrib;
                IERC20 long_t = IERC20(LONG_POSITION_TOKEN);
                long_t.transfer(msg.sender, excessQty);
            }
            longToSettle[msg.sender].addedQty -= contrib;
            uint positionQty = contrib.mul(longSettledValue).div(totalSettled);
            uint collateralQty = COLLATERAL_PER_UNIT.mul(positionQty);

            IMintable long = IMintable(LONG_POSITION_TOKEN);
            long.burn(address(this), contrib);
            collateral.transfer(msg.sender, collateralQty);
        }
    }

    function clearShortSettledTrade()
        external
    {
        // 20200430 MMcD: Post TAS retrieve the collateral from settlement
        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);

        if ((shortToSettle[msg.sender].addedQty > 0) &&
            (shortToSettle[msg.sender].initialQty < totalSettled)
        ) {
            uint contrib = shortToSettle[msg.sender].addedQty;
            uint excessQty = 0;
            if ((contrib + shortToSettle[msg.sender].initialQty) > totalSettled) {
                // Cap the amount of collateral that can be reclaimed to the total
                // settled in TAS auction
                contrib = totalSettled - shortToSettle[msg.sender].initialQty;
                // Transfer any uncrossed position tokens
                excessQty = shortToSettle[msg.sender].addedQty - contrib;
                IERC20 short_t = IERC20(SHORT_POSITION_TOKEN);
                short_t.transfer(msg.sender, excessQty);
            }
            shortToSettle[msg.sender].addedQty -= contrib;
            uint positionQty = contrib.mul(shortSettledValue).div(totalSettled);
            uint collateralQty = COLLATERAL_PER_UNIT.mul(positionQty);

            IMintable short = IMintable(SHORT_POSITION_TOKEN);
            short.burn(address(this), contrib);
            collateral.transfer(msg.sender, collateralQty);
        }
    }

    function isAddressWhiteListed(address contractAddress)
        external
        view
        returns (bool)
    {
        return contractWhitelist[contractAddress];
    }

    // Privileged methods: owner only

    function updateSpot(uint price)
        public
    {
        require(msg.sender == PRICE_UPDATE_ADDRESS, "ORACLE_ONLY");
        require(price >= PRICE_FLOOR && price <= PRICE_CAP, "arbitration price must be within contract bounds");
        PRICE_SPOT = price;
        // MMcD 20204030: Deal with trade at settlement orders
        // Currently only have single settlement event
        if ((totalLongToSettle > 0) && (totalShortToSettle > 0)) {
            if (totalLongToSettle >= totalShortToSettle) {
                totalSettled = totalShortToSettle;
            } else {
                totalSettled = totalLongToSettle;
            }
            totalLongToSettle -= totalSettled;
            totalShortToSettle -= totalSettled;
            longSettledValue = PRICE_SPOT.sub(PRICE_FLOOR).mul(totalSettled).div(PRICE_CAP.sub(PRICE_FLOOR));
            shortSettledValue = PRICE_CAP.sub(PRICE_SPOT).mul(totalSettled).div(PRICE_CAP.sub(PRICE_FLOOR));
            // redeemPositionTokens(address(this), totalSettled);
        }
    }

    function settleContract(uint finalSettlementPrice)
        public
    {
        require(msg.sender == owner, "OWNER_ONLY");
        settlementTimeStamp = now;
        settlementPrice = finalSettlementPrice;
        emit ContractSettled(finalSettlementPrice);
    }

    function arbitrateSettlement(uint256 price)
        public
    {
        require(msg.sender == owner, "OWNER_ONLY");
        require(price >= PRICE_FLOOR && price <= PRICE_CAP, "arbitration price must be within contract bounds");
        lastPrice = price;
        emit UpdatedLastPrice(price);
        settleContract(price);
        isSettled = true;
    }

    function settleAndClose(address, uint, uint) external {
        require(msg.sender == owner, "OWNER_ONLY");
        revert("NOT_IMPLEMENTED");
    }

    function addAddressToWhiteList(address contractAddress) external {
        require(msg.sender == owner, "OWNER_ONLY");
        contractWhitelist[contractAddress] = true;
    }
}