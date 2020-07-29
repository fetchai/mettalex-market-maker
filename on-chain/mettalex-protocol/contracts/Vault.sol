pragma solidity ^0.5.2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IMintable {
    function mint(address _to, uint256 _value) external;

    function burn(address _from, uint256 _value) external;
}

contract Vault {
    using SafeMath for uint256;

    string public CONTRACT_NAME = "Mettalex Vault";
    uint256 public PRICE_SPOT; // MMcD 20200430: Addition to interface to allow admin to set pricing
    uint256 public PRICE_CAP;
    uint256 public PRICE_FLOOR;
    uint256 public QTY_MULTIPLIER; // multiplier corresponding to the value of 1 increment in price to token base units
    uint256 public COLLATERAL_PER_UNIT; // required collateral amount for the full range of outcome tokens
    uint256 public COLLATERAL_TOKEN_FEE_PER_UNIT;

    // TO-DO: Check requirement of settlement params on contract completion
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

    constructor(
        address collateralToken,
        address longPositionToken,
        address shortPositionToken,
        address oracleAddress,
        address automatedMarketMaker,
        uint256 cap,
        uint256 floor,
        uint256 multiplier,
        uint256 feeRate
    ) public {
        // TO-DO: Update Pool logic
        COLLATERAL_POOL_ADDRESS = address(this);
        COLLATERAL_TOKEN_ADDRESS = collateralToken;
        LONG_POSITION_TOKEN = longPositionToken;
        SHORT_POSITION_TOKEN = shortPositionToken;
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

    function _calculateFee(uint256 quantityToMint)
        internal
        view
        returns (uint256)
    {
        if (msg.sender == AUTOMATED_MARKET_MAKER) return 0;
        return COLLATERAL_TOKEN_FEE_PER_UNIT.mul(quantityToMint);
    }

    function mintPositionTokens(uint256 quantityToMint) external {
        require(!isSettled, "Contract is already settled");

        IERC20 collateral = IERC20(COLLATERAL_TOKEN_ADDRESS);
        uint256 collateralRequired = COLLATERAL_PER_UNIT.mul(quantityToMint);
        uint256 collateralFeeRequired = _calculateFee(quantityToMint);

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

    // To:DO: Add breach logic
    function updateSpot(uint256 price) external {
        require(msg.sender == ORACLE_ADDRESS, "ORACLE_ONLY");
        require(
            price >= PRICE_FLOOR && price <= PRICE_CAP,
            "arbitration price must be within contract bounds"
        );
        PRICE_SPOT = price;

        emit UpdatedLastPrice(price);
    }

    // call within Priceupdate
    function settleContract()
        internal
        /*uint256 finalSettlementPrice*/
        onlyOwner
    {
        revert("NOT_IMPLEMENTED");
        //        settlementTimeStamp = now;
        //        settlementPrice = finalSettlementPrice;
        //        emit ContractSettled(finalSettlementPrice);
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
    function redeemPositionTokens(uint256 quantityToRedeem) external {
        redeemPositionTokens(msg.sender, quantityToRedeem);
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
}
