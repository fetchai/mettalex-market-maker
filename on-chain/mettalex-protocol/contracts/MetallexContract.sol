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
        uint index;
        uint initialQty;
        uint addedQty;
    }
    mapping (address => SettlementOrder) longToSettle;
    mapping (address => SettlementOrder) shortToSettle;

    // State variables that are cleared after each price update
    // These keep track of total long and short trade at settlement orders 
    // that have been submitted
    uint totalLongToSettle;
    uint totalShortToSettle;

    // Running count of number of price updates
    uint priceUpdateCount;
    
    // For each price update we store the total amount of position tokens that have been
    // settled using time at settlement orders, and the proportion of total value that 
    // goes to long and short positions.
    mapping(uint => uint) totalSettled;
    mapping(uint => uint) longSettledValue;
    mapping(uint => uint) shortSettledValue;

    uint public PRICE_CAP;
    uint public PRICE_FLOOR;
    uint public PRICE_DECIMAL_PLACES;   // how to convert the pricing from decimal format (if valid) to integer
    uint public QTY_MULTIPLIER;         // multiplier corresponding to the value of 1 increment in price to token base units
    uint public COLLATERAL_PER_UNIT;    // required collateral amount for the full range of outcome tokens
    uint public COLLATERAL_TOKEN_FEE_PER_UNIT;
    uint public lastPrice;
    uint public settlementPrice;
    uint public settlementTimeStamp;
    // TO-DO: Check requirement on contract completion
    bool public isSettled = false;

    address public COLLATERAL_TOKEN_ADDRESS;
    address public COLLATERAL_POOL_ADDRESS;
    address public LONG_POSITION_TOKEN;
    address public SHORT_POSITION_TOKEN;
    address public ORACLE_ADDRESS;

    mapping (address => bool) public contractWhitelist;

    event Mint(address indexed to, uint value);
    event Redeem(address indexed to, uint value);
    event UpdatedLastPrice(uint256 price);
    event ContractSettled(uint settlePrice);

    constructor(
        address collateralToken,
        address longPositionToken,
        address shortPositionToken,
        address oracleAddress,
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
        ORACLE_ADDRESS = oracleAddress;

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

        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "OWNER_ONLY");
        _;
    }

    function _clearSettledTrade(
        SettlementOrder order,
        uint settledValue,
        address positionTokenType,
        address sender
    )
        internal
    {
        // Post TAS retrieve the collateral from settlement
        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);

        if (order.addedQty > 0)
        {
            uint settleInd = order.index;
            require(settleInd < priceUpdateCount, "Can only clear previously settled order");
            uint contrib = order.addedQty;
            uint excessQty = 0;
            if ((contrib + order.initialQty) >= totalSettled[settleInd]) {
                // Cap the amount of collateral that can be reclaimed to the total
                // settled in TAS auction
                if (order.initialQty >= totalSettled[settleInd]) {
                    contrib = 0;
                } else {
                    contrib = totalSettled[settleInd] - order.initialQty;
                }
                // Transfer any uncrossed position tokens
                excessQty = order.addedQty - contrib;
            }

            uint positionQty = contrib.mul(settledValue).div(totalSettled[settleInd]);
            uint collateralQty = COLLATERAL_PER_UNIT.mul(positionQty);

            // Transfer any uncrossed position tokens
            IERC20 token = IERC20(positionTokenType);
            token.transfer(sender, excessQty);
            // Transfer reclaimed collateral
            collateral.transfer(sender, collateralQty);
        }
    }

    function priceUpdater()
        public
        view
        returns (address)
    {
        return ORACLE_ADDRESS;
    }

    function mintPositionTokens(
        uint qtyToMint
    )
        external
    {
        IMarketContract marketContract = IMarketContract(address(this));
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
        address to_address,  // Destination address for collateral redeemed
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
        // Destination address may not be the same as sender e.g. send to
        // exchange wallet receive funds address
        collateral.transfer(to_address, collateralToReturn);
    }

    // Overloaded method to redeem collateral to sender address
    function redeemPositionTokens(
        uint qtyToRedeem
    )
        public
    {
        redeemPositionTokens(msg.sender, qtyToRedeem);
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
                {index: priceUpdateCount, initialQty: totalLongToSettle, addedQty: qtyToTrade}
            );
            totalLongToSettle += qtyToTrade;
        } else {
            require(shortToSettle[msg.sender].addedQty == 0, "Single TAS order allowed" );
            shortToSettle[msg.sender] = SettlementOrder(
                {index: priceUpdateCount, initialQty: totalShortToSettle, addedQty: qtyToTrade}
            );
            totalShortToSettle += qtyToTrade;
        }
        position.transferFrom(msg.sender, address(this), qtyToTrade);
    }

    function clearLongSettledTrade()
        external
    {
        _clearSettledTrade(longToSettle[msg.sender], longSettledValue[longToSettle[msg.sender].index], LONG_POSITION_TOKEN, msg.sender);
        longToSettle[msg.sender].index = 0;
        longToSettle[msg.sender].addedQty = 0;
        longToSettle[msg.sender].initialQty = 0;
    }

    function clearShortSettledTrade()
        external
    {
        _clearSettledTrade(shortToSettle[msg.sender], shortSettledValue[shortToSettle[msg.sender].index], SHORT_POSITION_TOKEN, msg.sender);
        shortToSettle[msg.sender].index = 0;
        shortToSettle[msg.sender].addedQty = 0;
        shortToSettle[msg.sender].initialQty = 0;
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
        require(msg.sender == ORACLE_ADDRESS, "ORACLE_ONLY");
        require(price >= PRICE_FLOOR && price <= PRICE_CAP, "arbitration price must be within contract bounds");
        PRICE_SPOT = price;
        // Deal with trade at settlement orders
        // For each settlement event we store the total amount of position tokens crossed
        // and the total value of the long and short positions 
        if ((totalLongToSettle > 0) && (totalShortToSettle > 0)) {
            uint settled = 0;
            if (totalLongToSettle >= totalShortToSettle) {
                settled = totalShortToSettle;
            } else {
                settled = totalLongToSettle;
            }
            // Clear per period variables that track running total
            totalLongToSettle = 0;
            totalShortToSettle = 0;
            // Store position tokens settled amount and value going to long and short position
            longSettledValue[priceUpdateCount] = PRICE_SPOT.sub(
                PRICE_FLOOR).mul(settled).div(PRICE_CAP.sub(PRICE_FLOOR));
            shortSettledValue[priceUpdateCount] = PRICE_CAP.sub(
                PRICE_SPOT).mul(settled).div(PRICE_CAP.sub(PRICE_FLOOR));
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
    }

    function settleContract(uint finalSettlementPrice)
        public
        onlyOwner
    {
        revert("NOT_IMPLEMENTED");
//        settlementTimeStamp = now;
//        settlementPrice = finalSettlementPrice;
//        emit ContractSettled(finalSettlementPrice);
    }

    function arbitrateSettlement(uint256 price)
        public
        onlyOwner
    {
        revert("NOT_IMPLEMENTED");
//        require(price >= PRICE_FLOOR && price <= PRICE_CAP, "arbitration price must be within contract bounds");
//        lastPrice = price;
//        emit UpdatedLastPrice(price);
//        settleContract(price);
//        isSettled = true;
    }

    function settleAndClose(address, uint, uint) external onlyOwner{
        revert("NOT_IMPLEMENTED");
    }

    function addAddressToWhiteList(address contractAddress) external onlyOwner{
        contractWhitelist[contractAddress] = true;
    }
}