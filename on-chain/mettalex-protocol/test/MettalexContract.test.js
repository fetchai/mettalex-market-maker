const { accounts, contract } = require('@openzeppelin/test-environment');
const { expect } = require('chai');

const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

const CoinToken = contract.fromArtifact('CoinToken');
const MettalexContract = contract.fromArtifact('MettalexContract');
const PositionToken = contract.fromArtifact('PositionToken');

describe('MettalexContract', () => {
  const [owner, oracle, user, other] = accounts;

  before(async () => {
    this.collateralToken = await CoinToken.new('Tether', 'USDT', 18);
    this.longPositionToken = await PositionToken.new('LongToken', 'LTK', 6);
    this.shortPositionToken = await PositionToken.new('ShortToken', 'STK', 6);
    this.mettalexContract = await MettalexContract.new(
      this.collateralToken.address,
      this.longPositionToken.address,
      this.shortPositionToken.address,
      oracle,
      75000000,
      25000000,
      20000,
      300,
      { from: owner },
    );

    await this.collateralToken.setWhitelist(user, true);
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);
  });

  describe('Check initializations', () => {
    it('should check contract name', async () => {
      expect((await this.mettalexContract.CONTRACT_NAME()).toString()).to.equal('Mettalex');
    });

    it('should check spot price', async () => {
      expect((await this.mettalexContract.PRICE_SPOT()).toNumber()).to.equal(0);
    });


    it('should check price update count', async () => {
      expect((await this.mettalexContract.priceUpdateCount()).toNumber()).to.equal(0);
    });

    it('should check cap price', async () => {
      expect((await this.mettalexContract.PRICE_CAP()).toNumber()).to.equal(75000000);
    });

    it('should check floor price', async () => {
      expect((await this.mettalexContract.PRICE_FLOOR()).toNumber()).to.equal(25000000);
    });

    it('should check quantity multiplier', async () => {
      expect((await this.mettalexContract.QTY_MULTIPLIER()).toNumber()).to.equal(20000);
    });

    it('should check collateral per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_PER_UNIT()).toNumber()).to.equal(1000000000000);
    });

    it('should check collateral token fee per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_TOKEN_FEE_PER_UNIT()).toNumber()).to.equal(3000000000);
    });

    it('should check last price', async () => {
      expect((await this.mettalexContract.lastPrice()).toNumber()).to.equal(0);
    });

    it('should check settlement price', async () => {
      expect((await this.mettalexContract.settlementPrice()).toNumber()).to.equal(0);
    });

    it('should check price updater', async () => {
      expect((await this.mettalexContract.priceUpdater()).toString()).to.equal(oracle);
    });
  });

  describe('Mint position tokens', () => {
    before(async () => {
      await this.collateralToken.mint(user, 20060000000000);
    });

    it('should reject mint from user that is not whitelisted', async () => {
      await expectRevert(this.mettalexContract.mintPositionTokens(200, {from: other}), 'revert');
    });

    it('should revert if collateral cannot be transferred', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 999, {from: user});

      await expectRevert(this.mettalexContract.mintPositionTokens(200, {from: user}), 'revert');
    });

    it('should mint 10 long & 10 short position tokens', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 20060000000000, {from: user});

      const receipt = await this.mettalexContract.mintPositionTokens(10, {from: user});

      await expectEvent(receipt, 'LongPositionTokenMinted', {
        to: user,
        value: new BN(10),
        collateralRequired: new BN(10000000000000),
        collateralFeeRequired: new BN(30000000000),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(10);

      await expectEvent(receipt, 'ShortPositionTokenMinted', {
        to: user,
        value: new BN(10),
        collateralRequired: new BN(10000000000000),
        collateralFeeRequired: new BN(30000000000),
      });

      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(10);
    });
  });
});
