pragma solidity ^0.5.2;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract IToken {
    function balanceOf(address account) external view returns (uint256);

    function mint(address _to, uint256 _value) external;

    function burn(address _from, uint256 _value) external;

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract Vault {
    using SafeMath for uint256;

    string public CONTRACT_NAME;
    uint8 public VERSION;
    uint256 public PRICE_SPOT; // MMcD 20200430: Addition to interface to allow admin to set pricing
    uint256 public PRICE_CAP;
    uint256 public PRICE_FLOOR;
    uint256 public QTY_MULTIPLIER; // multiplier corresponding to the value of 1 increment in price to token base units
    uint256 public COLLATERAL_PER_UNIT; // required collateral amount for the full range of outcome tokens
    uint256 public COLLATERAL_TOKEN_FEE_PER_UNIT;

    uint8 constant MAX_SETTLEMENT_LENGTH = 150;
    uint256 public settlementPrice;
    uint256 public settlementTimeStamp;
    bool public isSettled = false;

    address public owner;
    address public COLLATERAL_TOKEN_ADDRESS;
    address public COLLATERAL_POOL_ADDRESS;
    address public LONG_POSITION_TOKEN;
    address public SHORT_POSITION_TOKEN;
    address public ORACLE_ADDRESS;
    address public AUTOMATED_MARKET_MAKER;

    event UpdatedLastPrice(uint256 price);
    event ContractSettled(uint256 settlePrice);
    event PositionsRedeemed(
        address indexed to,
        uint256 tokensBurned,
        uint256 collateralReturned
    );
    event PositionSettled(
        address indexed to,
        uint256 longTokensBurned,
        uint256 shortTokensBurned,
        uint256 collateralReturned
    );
    event PositionsMinted(
        address indexed to,
        uint256 value,
        uint256 collateralRequired,
        uint256 collateralFee
    );
    event PositionSettledInBulk(
        address[] _settlers,
        uint8 length,
        uint256 totalLongBurned,
        uint256 totalShortBurned,
        uint256 totalCollateralReturned
    );

    constructor(
        string memory name,
        uint8 version,
        address collateralToken,
        address longPosition,
        address shortPosition,
        address oracleAddress,
        address automatedMarketMaker,
        uint256 cap,
        uint256 floor,
        uint256 multiplier,
        uint256 feeRate
    ) public {
        CONTRACT_NAME = name;
        VERSION = version;
        COLLATERAL_POOL_ADDRESS = address(this);
        COLLATERAL_TOKEN_ADDRESS = collateralToken;
        LONG_POSITION_TOKEN = longPosition;
        SHORT_POSITION_TOKEN = shortPosition;
        ORACLE_ADDRESS = oracleAddress;
        AUTOMATED_MARKET_MAKER = automatedMarketMaker;

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

    modifier onlyOracle {
        require(msg.sender == ORACLE_ADDRESS, "ORACLE_ONLY");
        _;
    }

    modifier notSettled {
        require(!isSettled, "Contract is already settled");
        _;
    }

    modifier settled {
        require(isSettled, "Contract should be settled");
        _;
    }

    modifier withinMaxLength(uint8 settlerLength) {
        require(settlerLength <= MAX_SETTLEMENT_LENGTH);
        _;
    }

    function _calculateFee(uint256 quantityToMint)
        internal
        view
        returns (uint256)
    {
        if (msg.sender == AUTOMATED_MARKET_MAKER) return 0;
        return COLLATERAL_TOKEN_FEE_PER_UNIT.mul(quantityToMint);
    }

    function mintPositions(uint256 quantityToMint) external notSettled {
        IToken collateral = IToken(COLLATERAL_TOKEN_ADDRESS);
        uint256 collateralRequired = COLLATERAL_PER_UNIT.mul(quantityToMint);
        uint256 collateralFee = _calculateFee(quantityToMint);

        collateral.transferFrom(
            msg.sender,
            address(this),
            collateralRequired.add(collateralFee)
        );

        IToken long = IToken(LONG_POSITION_TOKEN);
        IToken short = IToken(SHORT_POSITION_TOKEN);

        long.mint(msg.sender, quantityToMint);
        short.mint(msg.sender, quantityToMint);
        emit PositionsMinted(
            msg.sender,
            quantityToMint,
            collateralRequired,
            collateralFee
        );
    }

    function updateSpot(uint256 price) external onlyOracle notSettled {
        // update spot if arbitration price is within contract bounds else settlecontract
        if (price >= PRICE_FLOOR && price <= PRICE_CAP) {
            PRICE_SPOT = price;
            emit UpdatedLastPrice(price);
        } else {
            _settleContract(price);
        }
    }

    function _settleContract(uint256 finalSettlementPrice) private {
        settlementTimeStamp = now;
        isSettled = true;
        settlementPrice = finalSettlementPrice;
        CONTRACT_NAME = string(abi.encodePacked(CONTRACT_NAME, " (settled)"));

        emit ContractSettled(finalSettlementPrice);
    }

    function updateOracle(address newOracle) external onlyOwner {
        ORACLE_ADDRESS = newOracle;
    }

    function updateAutomatedMarketMaker(address newAMM) external onlyOwner {
        AUTOMATED_MARKET_MAKER = newAMM;
    }

    function priceUpdater() external view returns (address) {
        return ORACLE_ADDRESS;
    }

    // Overloaded method to redeem collateral to sender address
    function redeemPositions(uint256 quantityToRedeem) external {
        redeemPositions(msg.sender, quantityToRedeem);
    }

    function redeemPositions(
        address to_address, // Destination address for collateral redeemed
        uint256 quantityToRedeem
    ) public {
        IToken long = IToken(LONG_POSITION_TOKEN);
        IToken short = IToken(SHORT_POSITION_TOKEN);
        long.burn(msg.sender, quantityToRedeem);
        short.burn(msg.sender, quantityToRedeem);

        IToken collateral = IToken(COLLATERAL_TOKEN_ADDRESS);
        uint256 collateralReturned = COLLATERAL_PER_UNIT.mul(quantityToRedeem);
        // Destination address may not be the same as sender e.g. send to
        // exchange wallet receive funds address
        collateral.transfer(to_address, collateralReturned);

        emit PositionsRedeemed(
            to_address,
            quantityToRedeem,
            collateralReturned
        );
    }

    function _settle(
        address settler,
        IToken collateral,
        IToken long,
        IToken short
    )
        private
        returns (
            uint256 longBurned,
            uint256 shortBurned,
            uint256 collateralConsumed
        )
    {
        uint256 longBalance = long.balanceOf(settler);
        uint256 shortBalance = short.balanceOf(settler);

        uint256 collateralReturned;
        if (settlementPrice < PRICE_FLOOR) {
            collateralReturned = COLLATERAL_PER_UNIT.mul(shortBalance);
        } else if (settlementPrice > PRICE_CAP) {
            collateralReturned = COLLATERAL_PER_UNIT.mul(longBalance);
        }

        long.burn(settler, longBalance);
        short.burn(settler, shortBalance);
        collateral.transfer(settler, collateralReturned);

        return (longBalance, shortBalance, collateralReturned);
    }

    function settlePositions() external settled {
        IToken collateral = IToken(COLLATERAL_TOKEN_ADDRESS);
        IToken long = IToken(LONG_POSITION_TOKEN);
        IToken short = IToken(SHORT_POSITION_TOKEN);

        (
            uint256 longBurned,
            uint256 shortBurned,
            uint256 collateralReturned
        ) = _settle(msg.sender, collateral, long, short);

        emit PositionSettled(
            msg.sender,
            longBurned,
            shortBurned,
            collateralReturned
        );
    }

    function bulkSettlePositions(address[] calldata _settlers)
        external
        onlyOwner
        settled
        withinMaxLength(uint8(_settlers.length))
    {
        uint256 totalLongBurned = 0;
        uint256 totalShortBurned = 0;
        uint256 totalCollateralReturned = 0;

        IToken collateral = IToken(COLLATERAL_TOKEN_ADDRESS);
        IToken long = IToken(LONG_POSITION_TOKEN);
        IToken short = IToken(SHORT_POSITION_TOKEN);

        uint8 index = 0;
        for (index; index < _settlers.length; index++) {
            (
                uint256 longBurned,
                uint256 shortBurned,
                uint256 collateralReturned
            ) = _settle(_settlers[index], collateral, long, short);
            totalLongBurned += longBurned;
            totalShortBurned += shortBurned;
            totalCollateralReturned += collateralReturned;
        }

        emit PositionSettledInBulk(
            _settlers,
            uint8(_settlers.length),
            totalLongBurned,
            totalShortBurned,
            totalCollateralReturned
        );
    }
}
