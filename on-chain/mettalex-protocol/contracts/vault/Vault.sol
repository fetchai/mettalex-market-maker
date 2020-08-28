pragma solidity ^0.5.2;

import "../interfaces/IToken.sol";
import "../libraries/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

contract Vault is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IToken;

    uint256 public version;
    uint256 public feeAccumulated;
    uint256 public priceSpot;
    uint256 public priceCap;
    uint256 public priceFloor;
    uint256 public qtyMultiplier; // multiplier corresponding to the value of 1 increment in price to token base units
    uint256 public collateralPerUnit; // required collateral amount for the full range of outcome tokens
    uint256 public collateralFeePerUnit;

    uint256 public settlementPrice;
    uint256 public settlementTimeStamp;
    address public collateralToken;
    address public longPositionToken;
    address public shortPositionToken;
    address public oracle;
    address public automatedMarketMaker;

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
    event AutomatedMarketMakerUpdated(
        address indexed _previousAMM,
        address indexed _newAMM
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

    constructor(
        string memory _name,
        uint256 _version,
        address _collateralToken,
        address _longPosition,
        address _shortPosition,
        address _oracleAddress,
        address _automatedMarketMaker,
        uint256 _cap,
        uint256 _floor,
        uint256 _multiplier,
        uint256 _feeRate
    ) public {
        contractName = _name;
        version = _version;
        collateralToken = _collateralToken;
        longPositionToken = _longPosition;
        shortPositionToken = _shortPosition;
        oracle = _oracleAddress;
        automatedMarketMaker = _automatedMarketMaker;

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

    modifier onlyOracle {
        require(msg.sender == oracle, "ORACLE_ONLY");
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
        require(
            settlerLength <= MAX_SETTLEMENT_LENGTH,
            "Cannot update more than 150 accounts"
        );
        _;
    }

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

    function updateSpot(uint256 _price) external onlyOracle notSettled {
        // update spot if arbitration price is within contract bounds else settlecontract
        if (_price >= priceFloor && _price <= priceCap) {
            priceSpot = _price;
            emit UpdatedLastPrice(_price);
        } else {
            _settleContract(_price);
        }
    }

    function claimFee(address _to) external onlyOwner {
        uint256 claimedCollateral = feeAccumulated;
        feeAccumulated = 0;

        IToken(collateralToken).safeTransfer(_to, claimedCollateral);
        emit FeeClaimed(_to, claimedCollateral);
    }

    function updateOracle(address _newOracle) external onlyOwner {
        emit OracleUpdated(oracle, _newOracle);
        oracle = _newOracle;
    }

    function updateAutomatedMarketMaker(address _newAMM) external onlyOwner {
        emit AutomatedMarketMakerUpdated(automatedMarketMaker, _newAMM);
        automatedMarketMaker = _newAMM;
    }

    // Overloaded method to redeem collateral to sender address
    function redeemPositions(uint256 _quantityToRedeem) external {
        redeemPositions(msg.sender, _quantityToRedeem);
    }

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

    function redeemPositions(
        address _to, // Destination address for collateral redeemed
        uint256 _redeemQuantity
    ) public {
        IToken(longPositionToken).burn(msg.sender, _redeemQuantity);
        IToken(shortPositionToken).burn(msg.sender, _redeemQuantity);

        uint256 collateralReturned = collateralPerUnit.mul(_redeemQuantity);
        // Destination address may not be the same as sender e.g. send to
        // exchange wallet receive funds address
        IToken(collateralToken).safeTransfer(_to, collateralReturned);

        emit PositionsRedeemed(_to, _redeemQuantity, collateralReturned);
    }

    function _calculateFee(uint256 _quantityToMint) internal returns (uint256) {
        if (msg.sender == automatedMarketMaker) return 0;

        uint256 collateralFee = collateralFeePerUnit.mul(_quantityToMint);
        feeAccumulated = feeAccumulated.add(collateralFee);
        return collateralFee;
    }

    function _calculateFeeAndPositions(uint256 _collateralAmount)
        internal
        returns (uint256, uint256)
    {
        if (msg.sender == automatedMarketMaker) {
            uint256 quantityToMint = _collateralAmount.div(collateralPerUnit);
            return (0, quantityToMint);
        }
        uint256 quantityToMint = _collateralAmount.div(
            collateralWithFeePerUnit
        );
        uint256 collateralFee = collateralFeePerUnit.mul(quantityToMint);
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

        uint256 collateralReturned;
        if (settlementPrice < priceFloor) {
            collateralReturned = collateralPerUnit.mul(shortBalance);
        } else if (settlementPrice > priceCap) {
            collateralReturned = collateralPerUnit.mul(longBalance);
        }

        _long.burn(_settler, longBalance);
        _short.burn(_settler, shortBalance);
        _collateral.safeTransfer(_settler, collateralReturned);

        return (longBalance, shortBalance, collateralReturned);
    }
}
