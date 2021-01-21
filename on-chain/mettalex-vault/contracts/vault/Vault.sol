pragma solidity ^0.5.2;

import "../interfaces/IToken.sol";
import "../libraries/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

/**
 * @title Vault
 */
contract Vault is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IToken;

    uint256 public version;
    uint256 public feeAccumulated;
    uint256 public priceSpot;
    uint256 public priceCap;
    uint256 public priceFloor;
    uint256 public qtyMultiplier;

    // required collateral amount for the full range of outcome tokens
    uint256 public collateralPerUnit;
    uint256 public collateralFeePerUnit;
    uint256 public settlementPrice;
    uint256 public settlementTimeStamp;
    address public collateralToken;
    address public longPositionToken;
    address public shortPositionToken;
    address public oracle;
    uint256 public settleFee = 0;
    //Automated market maker pool controller
    address public ammPoolController;

    string public contractName;
    bool public isSettled = false;

    uint8 private constant MAX_SETTLEMENT_LENGTH = 120;
    uint256 private collateralWithFeePerUnit;

    event UpdatedLastPrice(uint256 _price);
    event ContractSettled(uint256 indexed _settlePrice);
    event FeeClaimed(address indexed _payee, uint256 _weiAmount);
    event OracleUpdated(
        address indexed _previousOracle,
        address indexed _newOracle
    );
    //AMM - Automated market maker
    event AMMPoolControllerUpdated(
        address indexed _previousAMMPoolController,
        address indexed _newAMMPoolController
    );
    event PositionsRedeemed(
        address indexed _to,
        uint256 _tokensBurned,
        uint256 _collateralReturned
    );
    event PositionSettled(
        address indexed _settler,
        uint256 _longTokensBurned,
        uint256 _shortTokensBurned,
        uint256 _collateralReturned
    );
    event PositionsMinted(
        address indexed _to,
        uint256 _value,
        uint256 _collateralRequired,
        uint256 _collateralFee
    );
    event PositionSettledInBulk(
        address[] _settlers,
        uint8 _length,
        uint256 _totalLongBurned,
        uint256 _totalShortBurned,
        uint256 _totalCollateralReturned
    );

    /**
     * @dev The Vault constructor sets initial values
     * @param _name string The name of the Vault
     * @param _version uint256 The version of the Vault
     * @param _collateralToken address The address of the collateral token
     * @param _longPosition address The collateral token address
     * @param _shortPosition address The short position token address
     * @param _oracleAddress address The long position token address
     * @param _ammPoolController address The AMM (Automated market maker) pool
     * controller address
     * @param _cap uint256 The cap for asset price
     * @param _floor uint256 The floor for asset price
     * @param _multiplier uint256 multiplier corresponding to the value of 1
     * increment in price to token base units
     * @param _feeRate uint256 The fee rate for locking collateral
     */
    constructor(
        string memory _name,
        uint256 _version,
        address _collateralToken,
        address _longPosition,
        address _shortPosition,
        address _oracleAddress,
        address _ammPoolController,
        uint256 _cap,
        uint256 _floor,
        uint256 _multiplier,
        uint256 _feeRate
    ) public {
        require(_collateralToken != address(0));
        require(_longPosition != address(0));
        require(_shortPosition != address(0));
        require(
        (_collateralToken != _longPosition) &&
        (_collateralToken != _shortPosition) &&
        (_longPosition != _shortPosition)
        );
        require(_oracleAddress != address(0));
        require(_ammPoolController != address(0));

        contractName = _name;
        version = _version;
        collateralToken = _collateralToken;
        longPositionToken = _longPosition;
        shortPositionToken = _shortPosition;
        oracle = _oracleAddress;
        ammPoolController = _ammPoolController;

        priceCap = _cap;
        priceFloor = _floor;
        qtyMultiplier = _multiplier;
        collateralPerUnit = _cap.sub(_floor).mul(_multiplier);
        collateralFeePerUnit = _cap
            .add(_floor)
            .mul(_multiplier)
            .mul(_feeRate)
            .div(200000);
        collateralWithFeePerUnit = collateralPerUnit.add(collateralFeePerUnit);
    }

    /**
     * @dev Throws if called by any account other than Oracle
     */
    modifier onlyOracle {
        require(msg.sender == oracle, "ORACLE_ONLY");
        _;
    }

    /**
     * @dev Throws if contract is settled
     */
    modifier notSettled {
        require(!isSettled, "Contract is already settled");
        _;
    }

    /**
     * @dev Throws if contract is not settled
     */
    modifier settled {
        require(isSettled, "Contract should be settled");
        _;
    }

    /**
     * @dev Throws if more than max-allowed number of addresses passed to settle
     */
    modifier withinMaxLength(uint8 settlerLength) {
        require(
            settlerLength <= MAX_SETTLEMENT_LENGTH,
            "Cannot update more than 150 accounts"
        );
        _;
    }

    /**
     * @dev Used to claim fee accumulated by the vault
     * @param _to address The address to transfer the fee
     */
    function claimFee(address _to) external onlyOwner {
        require(
            (_to != address(0)) && (_to != address(this)),
            "invalid to address"
        );

        uint256 claimedCollateral = feeAccumulated;
        feeAccumulated = 0;

        IToken(collateralToken).safeTransfer(_to, claimedCollateral);
        emit FeeClaimed(_to, claimedCollateral);
    }

    /**
     * @dev Changes the spot price of an asset
     * @param _price uint256 The updated price
     */
    function updateSpot(uint256 _price) external onlyOracle notSettled {
        // update spot if arbitration price is within contract bounds else settlecontract
        if (_price >= priceFloor && _price <= priceCap) {
            priceSpot = _price;
            emit UpdatedLastPrice(_price);
        } else {
            _settleContract(_price);
        }
    }

    /**
     * @dev Changes the address of Oracle contract
     * @param _newOracle address The address of new oracle contract
     */
    function updateOracle(address _newOracle) external onlyOwner {
        require(
            (_newOracle != address(0)) && (_newOracle != address(this)),
            "invalid oracle address"
        );   
        emit OracleUpdated(oracle, _newOracle);
        oracle = _newOracle;
    }

    /**
     * @dev Changes the settle fee
     * @param newSettleFee new settleFee
     */
    function updateSettleFee(uint256 newSettleFee) external onlyOwner{
        require(newSettleFee <= (10**3), "ERR_MAX_SETTLE_FEE");
        settleFee = newSettleFee;
    }

    /**
     * @dev Changes the address of Automated Market Maker
     * @param _newAMMPoolController address The address of new AMM (automated market maker)
     * pool controller address
     */
    function updateAMMPoolController(address _newAMMPoolController)
        external
        onlyOwner
    {
        require(
        (_newAMMPoolController != address(0)) && (_newAMMPoolController !=
        address(this)),
        "invalid amm pool controller"
        );
        emit AMMPoolControllerUpdated(ammPoolController, _newAMMPoolController);
        ammPoolController = _newAMMPoolController;
    }

    /**
     * @dev Mints the Long and Short position tokens
     * @param _quantityToMint uint256 The amount of positions to be minted
     */
    function mintPositions(uint256 _quantityToMint) external notSettled {
        uint256 collateralRequired = collateralPerUnit.mul(_quantityToMint);
        uint256 collateralFee = _calculateFee(_quantityToMint);

        IToken(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateralRequired.add(collateralFee)
        );

        IToken(longPositionToken).mint(msg.sender, _quantityToMint);
        IToken(shortPositionToken).mint(msg.sender, _quantityToMint);
        emit PositionsMinted(
            msg.sender,
            _quantityToMint,
            collateralRequired,
            collateralFee
        );
    }

    /**
     * @dev Mints the Long and Short position tokens based on amount of collateral
     * @param _collateralAmount uint256 The amount of collateral to be deposited
     */
    function mintFromCollateralAmount(uint256 _collateralAmount)
        external
        notSettled
    {
        (
            uint256 collateralFee,
            uint256 quantityToMint
        ) = _calculateFeeAndPositions(_collateralAmount);

        IToken(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            _collateralAmount
        );

        IToken(longPositionToken).mint(msg.sender, quantityToMint);
        IToken(shortPositionToken).mint(msg.sender, quantityToMint);
        emit PositionsMinted(
            msg.sender,
            quantityToMint,
            _collateralAmount.sub(collateralFee),
            collateralFee
        );
    }

    /**
     * @dev Redeems the given amount of positions held by user
     * @dev Overloaded method to redeem collateral to sender address
     * @param _quantityToRedeem uint256 The quantity of position tokens to redeem
     */

    function redeemPositions(uint256 _quantityToRedeem) external {
        redeemPositions(msg.sender, _quantityToRedeem);
    }

    /**
     * @dev Settles by returning collateral and burning positions
     */
    function settlePositions() external settled {
        (
            uint256 longBurned,
            uint256 shortBurned,
            uint256 collateralReturned
        ) = _settle(
            msg.sender,
            IToken(collateralToken),
            IToken(longPositionToken),
            IToken(shortPositionToken)
        );

        emit PositionSettled(
            msg.sender,
            longBurned,
            shortBurned,
            collateralReturned
        );
    }

    /**
     * @dev Settles multiple addresses at once
     * @param _settlers address[] The array of user accounts to settle
     */
    function bulkSettlePositions(address[] calldata _settlers)
        external
        onlyOwner
        settled
        withinMaxLength(uint8(_settlers.length))
    {
        uint256 totalLongBurned;
        uint256 totalShortBurned;
        uint256 totalCollateralReturned;

        IToken collateral = IToken(collateralToken);
        IToken long = IToken(longPositionToken);
        IToken short = IToken(shortPositionToken);

        uint8 index = 0;
        for (index; index < _settlers.length; index++) {
            (
                uint256 longBurned,
                uint256 shortBurned,
                uint256 collateralReturned
            ) = _settle(_settlers[index], collateral, long, short);
            totalLongBurned = totalLongBurned.add(longBurned);
            totalShortBurned = totalShortBurned.add(shortBurned);
            totalCollateralReturned = totalCollateralReturned.add(collateralReturned);
        }

        emit PositionSettledInBulk(
            _settlers,
            uint8(_settlers.length),
            totalLongBurned,
            totalShortBurned,
            totalCollateralReturned
        );
    }

    /**
     * @dev Redeems the given amount of positions held by user
     * @param _to address The address of user to transfer the collateral redeemed
     * @param _redeemQuantity uint256 The amount of positions to redeem
     */
    function redeemPositions(address _to, uint256 _redeemQuantity) public {
        IToken(longPositionToken).burn(msg.sender, _redeemQuantity);
        IToken(shortPositionToken).burn(msg.sender, _redeemQuantity);

        uint256 collateralReturned = collateralPerUnit.mul(_redeemQuantity);
        // Destination address may not be the same as sender e.g. send to
        // exchange wallet receive funds address
        IToken(collateralToken).safeTransfer(_to, collateralReturned);

        emit PositionsRedeemed(_to, _redeemQuantity, collateralReturned);
    }

    function _calculateFee(uint256 _quantityToMint) internal returns (uint256) {
        if (msg.sender == ammPoolController) return 0;

        uint256 collateralFee = collateralFeePerUnit.mul(_quantityToMint);
        feeAccumulated = feeAccumulated.add(collateralFee);
        return collateralFee;
    }

    function _calculateFeeAndPositions(uint256 _collateralAmount)
        internal
        returns (uint256, uint256)
    {
        if (msg.sender == ammPoolController) {
            uint256 quantityToMint = _collateralAmount.div(collateralPerUnit);
            return (0, quantityToMint);
        }
        uint256 quantityToMint = _collateralAmount.div(
            collateralWithFeePerUnit
        );
        uint256 collateralFee = _collateralAmount
        .mul(collateralFeePerUnit)
        .div(collateralWithFeePerUnit);
        feeAccumulated = feeAccumulated.add(collateralFee);
        return (collateralFee, quantityToMint);
    }

    function _settleContract(uint256 _settlementPrice) private {
        settlementTimeStamp = now;
        isSettled = true;
        settlementPrice = _settlementPrice;
        contractName = string(abi.encodePacked(contractName, " (settled)"));

        emit ContractSettled(_settlementPrice);
    }

    function _settle(
        address _settler,
        IToken _collateral,
        IToken _long,
        IToken _short
    )
        private
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 longBalance = _long.balanceOf(_settler);
        uint256 shortBalance = _short.balanceOf(_settler);
        uint256 fractionReturned = 1000;
        if (msg.sender != ammPoolController) {
            fractionReturned = fractionReturned.sub(settleFee);
        }
        uint256 collateralReturned;
        uint256 collateralAmount;
        if (settlementPrice < priceFloor) {
            collateralAmount = collateralPerUnit.mul(shortBalance);
            collateralReturned = collateralPerUnit.mul(shortBalance.mul(fractionReturned).div(1000));
        } else if (settlementPrice > priceCap) {
            collateralAmount = collateralPerUnit.mul(longBalance);
            collateralReturned = collateralPerUnit.mul(longBalance.mul(fractionReturned).div(1000));
        }

        _long.burn(_settler, longBalance);
        _short.burn(_settler, shortBalance);
        _collateral.safeTransfer(_settler, collateralReturned);

        feeAccumulated = feeAccumulated.add(collateralAmount.sub(collateralReturned));

        return (longBalance, shortBalance, collateralReturned);
    }
}   