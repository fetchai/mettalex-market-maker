const { accounts, contract } = require('@openzeppelin/test-environment');
const { expect } = require('chai');

const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

const CoinToken = contract.fromArtifact('CoinToken');
const MettalexContract = contract.fromArtifact('MettalexContract');
const PositionToken = contract.fromArtifact('PositionToken');

describe('MettalexContract', () => {
  const [owner, oracle, user, other] = accounts;
  const nullAddress = '0x0000000000000000000000000000000000000000';

  before(async () => {
    this.collateralToken = await CoinToken.new('Tether', 'USDT', 18);
    this.longPositionToken = await PositionToken.new('LongToken', 'LTK', 6);
    this.shortPositionToken = await PositionToken.new('ShortToken', 'STK', 6);
    this.mettalexContract = await MettalexContract.new(
      this.collateralToken.address,
      this.longPositionToken.address,
      this.shortPositionToken.address,
      oracle,
      62500000,
      37500000,
      100000000,
      300,
      { from: owner },
    );
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
      expect((await this.mettalexContract.PRICE_CAP()).toNumber()).to.equal(62500000);
    });

    it('should check floor price', async () => {
      expect((await this.mettalexContract.PRICE_FLOOR()).toNumber()).to.equal(37500000);
    });

    it('should check quantity multiplier', async () => {
      expect((await this.mettalexContract.QTY_MULTIPLIER()).toNumber()).to.equal(100000000);
    });

    it('should check collateral per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_PER_UNIT()).toNumber()).to.equal(2500000000000000);
    });

    it('should check collateral token fee per unit', async () => {
      expect((await this.mettalexContract.COLLATERAL_TOKEN_FEE_PER_UNIT()).toNumber()).to.equal(15000000000000);
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
    const tokensToMint = 10;
    const requiredCollateral = new BN('25150000000000000');

    beforeEach(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(user, requiredCollateral);
      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user});
    });

    afterEach(async () => {
      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(user)).toString());
      await this.collateralToken.burn(user, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    after(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, requiredCollateral);
      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user});

      await this.mettalexContract.redeemPositionTokens(10, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(this.mettalexContract.address)).toString());
      await this.collateralToken.burn(this.mettalexContract.address, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });
    
    // TO-DO: Complete upon implementation of settleContract in MettalexContract
    it('should reject mint if contract is settled');

    it('should reject mint from user that is not whitelisted in collateral token', async () => {
      await this.collateralToken.setWhitelist(user, false);

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: other}), 'revert');
    });

    it('should reject mint from user if contract is not whitelisted in long position token', async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: other}), 'revert');
    });
    
    it('should reject mint from user if contract is not whitelisted in short position token', async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: other}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to insufficient collateral funds in user account', async () => {
      await this.collateralToken.burn(user, requiredCollateral);

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: user}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 999, {from: user});

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: user}), 'revert');
    });

    it('should mint 10 long & 10 short position tokens', async () => {
      const receipt = await this.mettalexContract.mintPositionTokens(tokensToMint, {from: user});

      await expectEvent(receipt, 'LongPositionTokenMinted', {
        to: user,
        value: new BN(tokensToMint),
        collateralRequired: new BN('25000000000000000'),
        collateralFeeRequired: new BN('150000000000000'),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(tokensToMint);

      await expectEvent(receipt, 'ShortPositionTokenMinted', {
        to: user,
        value: new BN(tokensToMint),
        collateralRequired: new BN('25000000000000000'),
        collateralFeeRequired: new BN('150000000000000'),
      });

      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(tokensToMint);
    });
  });

  describe('Redeem position tokens', () => {
    const tokensToRedeem = 10;
    const requiredCollateral = new BN('25150000000000000');

    before(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(user, new BN('25150000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('25150000000000000'), {from: user});

      await this.mettalexContract.mintPositionTokens(10, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(user)).toString());
      await this.collateralToken.burn(user, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    beforeEach(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, requiredCollateral);
      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user});
    });

    afterEach(async () => {
      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(this.mettalexContract.address)).toString());
      await this.collateralToken.burn(this.mettalexContract.address, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });
  
    // TO-DO
    // it('should revert if sender\'s address is invalid', async () => {
    //   await this.collateralToken.setWhitelist(nullAddress, true);

    //   await this.collateralToken.mint(this.mettalexContract.address, requiredCollateral);
    //   await expectRevert(await this.mettalexContract.redeemPositionTokens(nullAddress, tokensToRedeem), 'INVALID_ADDRESS');
    // });

    it('should revert if user is not whitelisted in collateral token', async () => {
      await this.collateralToken.setWhitelist(user, false);

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: other}), 'revert');
    });

    it('should revert if contract is not whitelisted in long position token', async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: other}), 'revert');
    });

    it('should revert if contract is not whitelisted in short position token', async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: other}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to insufficient collateral funds in contract\'s collateral pool', async () => {
      await this.collateralToken.burn(this.mettalexContract.address, requiredCollateral);

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: user}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 999, {from: user});

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToRedeem, {from: user}), 'revert');
    });

    it('should revert if sender has insufficient tokens to redeem', async () => {
      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: other}), 'revert');
    });

    it('should revert if sender redeems more than total minted position tokens', async () => {
      await expectRevert(this.mettalexContract.redeemPositionTokens(11, {from: user}), 'revert');
    });

    it('should redeem 10 long and 10 short position tokens', async () => {
      const initialLongTokens = await this.longPositionToken.balanceOf(user);
      const initialShortTokens = await this.shortPositionToken.balanceOf(user);

      const receipt = await this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: user});
      await expectEvent(receipt, 'Redeem', {
        to: user,
        burntTokenQuantity: new BN(tokensToRedeem),
        collateralToReturn: new BN('25000000000000000'),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(initialLongTokens - tokensToRedeem);
      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(initialShortTokens - tokensToRedeem);
    });
  });

  describe('Trade at settlement', () => {
    const tokensToInvest = 2;

    before(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(user, new BN('25150000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('25150000000000000'), {from: user});

      await this.mettalexContract.mintPositionTokens(10, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(user)).toString());
      await this.collateralToken.burn(user, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    beforeEach(async () => {
      await this.longPositionToken.approve(this.mettalexContract.address, 2, {from: user});
      await this.shortPositionToken.approve(this.mettalexContract.address, 2, {from: user});
    });

    afterEach(async () => {
      await this.longPositionToken.approve(this.mettalexContract.address, 0, {from: user});
      await this.shortPositionToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    after(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, new BN('201200000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('201200000000000000'), {from: user});

      await this.mettalexContract.redeemPositionTokens(8, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(this.mettalexContract.address)).toString());
      await this.collateralToken.burn(this.mettalexContract.address, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    it('should reject call without either of long or short token', async () => {
      await expectRevert(this.mettalexContract.tradeAtSettlement(other, tokensToInvest, {from: user}), 'Given address must be either of Long Position Token or Short Position Token');
    });

    it('should reject call if contract not approved to transfer long or short tokens', async () => {
      await this.longPositionToken.approve(this.mettalexContract.address, 0, {from: user});
      await this.shortPositionToken.approve(this.mettalexContract.address, 0, {from: user});

      await expectRevert(this.mettalexContract.tradeAtSettlement(this.longPositionToken.address, tokensToInvest, {from: user}), 'revert');

      await expectRevert(this.mettalexContract.tradeAtSettlement(this.shortPositionToken.address, tokensToInvest, {from: user}), 'revert');
    });

    it('should reject call if user makes TAS order with more than its balance of long or short tokens', async () => {
      await expectRevert(this.mettalexContract.tradeAtSettlement(this.longPositionToken.address, 11, {from: user}), 'revert');

      await expectRevert(this.mettalexContract.tradeAtSettlement(this.shortPositionToken.address, 11, {from: user}), 'revert');
    });

    it('should invest 2 long tokens in stock', async () => {
      const initialLongTokens = await this.longPositionToken.balanceOf(user);

      const receipt = await this.mettalexContract.tradeAtSettlement(this.longPositionToken.address, tokensToInvest, {from: user});

      await expectEvent(receipt, 'OrderedLongTAS', {
        from: user,
        orderIndex: new BN(0),
        initialTotalLongToSettle: new BN(0),
        quantityToTrade: new BN(tokensToInvest),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(initialLongTokens - 2);
    });

    it('should invest 2 short tokens in stock', async () => {
      const initialShortTokens = await this.shortPositionToken.balanceOf(user);

      const receipt = await this.mettalexContract.tradeAtSettlement(this.shortPositionToken.address, tokensToInvest, {from: user});

      await expectEvent(receipt, 'OrderedShortTAS', {
        from: user,
        orderIndex: new BN(0),
        initialTotalShortToSettle: new BN(0),
        quantityToTrade: new BN(tokensToInvest),
      });

      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(initialShortTokens - 2);
    });

    it('should disallow multiple trade at settlement orders with long position token', async () => {
      await expectRevert(this.mettalexContract.tradeAtSettlement(this.longPositionToken.address, tokensToInvest, {from: user}), 'Single TAS order allowed');
    });

    it('should disallow multiple trade at settlement orders with short position token', async () => {
      await expectRevert(this.mettalexContract.tradeAtSettlement(this.shortPositionToken.address, tokensToInvest, {from: user}), 'Single TAS order allowed');
    });
  });

  describe('updateSpot', () => {
    const requiredCollateral = new BN('5030000000000000');

    before(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(user, new BN('25150000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('25150000000000000'), {from: user});

      await this.mettalexContract.mintPositionTokens(10, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(user)).toString());
      await this.collateralToken.burn(user, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    beforeEach(async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, requiredCollateral);
      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user});
    });

    afterEach(async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(this.mettalexContract.address)).toString());
      await this.collateralToken.burn(this.mettalexContract.address, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });

    after(async () => {
      await this.collateralToken.setWhitelist(user, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, new BN('201200000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('201200000000000000'), {from: user});

      await this.mettalexContract.redeemPositionTokens(8, {from: user});

      await this.collateralToken.setWhitelist(user, false);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

      const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(this.mettalexContract.address)).toString());
      await this.collateralToken.burn(this.mettalexContract.address, remainingCollateralToken);
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});
    });
    
    // it('should reject call from address other than price updater', async () => {
    //   await expectRevert(this.mettalexContract.updateSpot(20000000, {from: user}), 'ORACLE_ONLY');
    // });

    // it('should reject price update on breach', async () => {
    //   await expectRevert(this.mettalexContract.updateSpot(24000000, {from: oracle}), 'arbitration price must be within contract bounds');
    // });

    // it('should reject price update if contract is not whitelisted in long position token', async () => {
    //   await this.longPositionToken.setWhitelist(this.mettalexContract.address, false);

    //   await expectRevert(this.mettalexContract.updateSpot(44000000, {from: oracle}), 'WHITELISTED_ONLY');
    // });
    
    // it('should reject price update if contract is not whitelisted in short position token', async () => {
    //   await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false);

    //   await expectRevert(this.mettalexContract.updateSpot(44000000, {from: oracle}), 'WHITELISTED_ONLY');
    // });

    it('should update spot price & deal with TAS orders', async () => {
      const initialLongTokens = await this.longPositionToken.balanceOf(this.mettalexContract.address);
      const initialShortTokens = await this.shortPositionToken.balanceOf(this.mettalexContract.address);
      const initialPriceUpdateCount = (await this.mettalexContract.priceUpdateCount()).toNumber();

      const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
      await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});
      await this.mettalexContract.updateSpot(44000000, {from: oracle});

      expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialLongTokens - 2);
      expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialShortTokens - 2);

      expect((await this.mettalexContract.priceUpdateCount()).toNumber()).to.equal(initialPriceUpdateCount + 1);
    });

    //to-do
    // it('should update spot price & not deal with TAS orders as neither long nor short TAS order exists', async () => {
    //   const initialLongTokens = (await this.longPositionToken.balanceOf(this.mettalexContract.address)).toNumber();
    //   const initialShortTokens = (await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toNumber();
    //   const initialPriceUpdateCount = (await this.mettalexContract.priceUpdateCount()).toNumber();

    //   const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
    //   await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});
    //   await this.mettalexContract.updateSpot(44000000, {from: oracle});

    //   expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialLongTokens);
    //   expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialShortTokens);

    //   expect((await this.mettalexContract.priceUpdateCount()).toNumber()).to.equal(initialPriceUpdateCount);
    // });
  });

  describe('Clear Settled Trade', () => {
    before(async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true);
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, true);

      await this.collateralToken.mint(this.mettalexContract.address, new BN('5030000000000000'));
      await this.collateralToken.approve(this.mettalexContract.address, new BN('5030000000000000'), {from: user});
    });
    //to-do add new order & cover test case of priceUpdateCnt
    it('should change nothing for user who never made TAS order', async () => {
      const initialCollateralTokens = (await this.collateralToken.balanceOf(other)).toNumber();
      const initialLongTokens = (await this.longPositionToken.balanceOf(other)).toNumber();
      const initialShortTokens = (await this.shortPositionToken.balanceOf(other)).toNumber();

      await this.mettalexContract.clearLongSettledTrade({from: other});
      await this.mettalexContract.clearShortSettledTrade({from: other});

      expect((await this.collateralToken.balanceOf(other)).toNumber()).to.equal(initialCollateralTokens);
      expect((await this.longPositionToken.balanceOf(other)).toNumber()).to.equal(initialLongTokens);
      expect((await this.shortPositionToken.balanceOf(other)).toNumber()).to.equal(initialShortTokens);
    });
    //to-do cover cases of different type of clearing- full contrib, half, none (long/short diff)
    it('should clear user\'s long position token investment', async () => {
      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user)).toString());
      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(user)).toString());

      const receipt = await this.mettalexContract.clearLongSettledTrade({from: user});

      await expectEvent(receipt, 'ClearedLongSettledTrade', {
        sender: user,
        settledValue: new BN(0),
        senderContribution: new BN(2),
        senderExcess: new BN(0),
        positionQuantity: new BN(0),
        collateralQuantity: new BN(0),
      });

      expect((await this.collateralToken.balanceOf(user)).toString()).to.equal(initialCollateralTokens.toString());
      expect((await this.longPositionToken.balanceOf(user)).toString()).to.equal(initialLongTokens.toString());
    });

    it('should clear user\'s short position token investment', async () => {
      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(user)).toString());

      const receipt = await this.mettalexContract.clearShortSettledTrade({
        from: user
      });

      await expectEvent(receipt, 'ClearedShortSettledTrade', {
        sender: user,
        settledValue: new BN(1),
        senderContribution: new BN(2),
        senderExcess: new BN(0),
        positionQuantity: new BN(1),
        collateralQuantity: new BN('2500000000000000'),
      });

      expect((await this.collateralToken.balanceOf(user)).toString()).to.equal('22500000000000000');
      expect((await this.shortPositionToken.balanceOf(user)).toString()).to.equal(initialShortTokens.toString());
    });
  });

  describe('WhiteList operations', () => {
    it('should revert as not called by owner', async () => {
      await expectRevert(this.mettalexContract.addAddressToWhiteList(user, {from: other}), 'OWNER_ONLY');
    });

    it('should add address to WhiteList', async () => {
      expect((await this.mettalexContract.contractWhitelist(user)).toString()).to.equal('false');

      await this.mettalexContract.addAddressToWhiteList(user, {from: owner});

      expect((await this.mettalexContract.contractWhitelist(user)).toString()).to.equal('true');
    });
  });
});
//to-do chk coverage