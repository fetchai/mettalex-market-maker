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
  });

  describe('Check initializations', () => {
    it('should check contract name', async () => {
      expect((await this.mettalexContract.CONTRACT_NAME()).toString()).to.equal('Mettalex');
    });

    it('should check spot price', async () => {
      expect((await this.mettalexContract.PRICE_SPOT()).toString()).to.equal('0');
    });


    it('should check price update count', async () => {
      expect((await this.mettalexContract.priceUpdateCount()).toString()).to.equal('0');
    });

    it('should check cap price', async () => {
      expect((await this.mettalexContract.PRICE_CAP()).toString()).to.equal('75000000');
    });

    it('should check floor price', async () => {
      expect((await this.mettalexContract.PRICE_FLOOR()).toString()).to.equal('25000000');
    });

    it('should check quantity multiplier', async () => {
      expect((await this.mettalexContract.QTY_MULTIPLIER()).toString()).to.equal('20000');
    });

    it('should check collateral per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_PER_UNIT()).toString()).to.equal('1000000000000');
    });

    it('should check collateral token fee per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_TOKEN_FEE_PER_UNIT()).toString()).to.equal('3000000000');
    });

    it('should check last price', async () => {
      expect((await this.mettalexContract.lastPrice()).toString()).to.equal('0');
    });

    it('should check settlement price', async () => {
      expect((await this.mettalexContract.settlementPrice()).toString()).to.equal('0');
    });

    it('should check price updater', async () => {
      expect((await this.mettalexContract.priceUpdater()).toString()).to.equal(oracle);
    });
  });
});
