const { accounts, contract } = require('@openzeppelin/test-environment');
const { expect } = require('chai');

const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

const CoinToken = contract.fromArtifact('CoinToken');
const MettalexContract = contract.fromArtifact('MettalexContract');
const PositionToken = contract.fromArtifact('PositionToken');

describe('MettalexContract', () => {
  const [owner, oracle, user, user2, user3, user4, user5, user6, user7, other] = accounts;
  const nullAddress = '0x0000000000000000000000000000000000000000';

  before(async () => {
    this.collateralToken = await CoinToken.new('Tether', 'USDT', 18, { from: owner });
    this.longPositionToken = await PositionToken.new('LongToken', 'LTK', 6, { from: owner });
    this.shortPositionToken = await PositionToken.new('ShortToken', 'STK', 6, { from: owner });
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

  const _getCollateral = async (account, collateral) => {
    const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(account)).toString());

    if (collateral.sub(remainingCollateralToken) > new BN(0))
      await this.collateralToken.transfer(account, collateral.sub(remainingCollateralToken), { from: owner });
  };

  const _burnCollateral = async (account) => {
    const remainingCollateralToken = new BN((await this.collateralToken.balanceOf(account)).toString());
    await this.collateralToken.burn(account, remainingCollateralToken, { from: owner });
  }; 

  const _setupForMinting = async (account, collateral) => {
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });

    await this.collateralToken.transfer(account, collateral, {from: owner});
    await this.collateralToken.approve(this.mettalexContract.address, collateral, {from: account});
  };

  const _endMinting = async (account) => {
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

    await this.collateralToken.approve(this.mettalexContract.address, 0, { from: account });
  };

  const _setupForRedeeming = async (account, collateral) => {
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });

    await this.collateralToken.transfer(this.mettalexContract.address, collateral, { from: owner });
    await this.collateralToken.approve(this.mettalexContract.address, collateral, {from: account});
  };

  const _endRedeeming = async (account) => {
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

    await this.collateralToken.approve(this.mettalexContract.address, 0, {from: account});
  };

  const _setupForTASOrder = async (account, investment) => {
    await this.longPositionToken.approve(this.mettalexContract.address, investment, {from: account});
    await this.shortPositionToken.approve(this.mettalexContract.address, investment, {from: account});
  };

  const _endTASOrder = async (account) => {
    await this.longPositionToken.approve(this.mettalexContract.address, 0, {from: account});
    await this.shortPositionToken.approve(this.mettalexContract.address, 0, {from: account});
  };

  const _makeTASOrder = async (account, positionToken, investment) => {
    const initialTokens = 6;
    const requiredCollateral = new BN('15090000000000000');
    await _setupForMinting(account, requiredCollateral);
    await this.mettalexContract.mintPositionTokens(initialTokens, {from: account});
    await _endMinting(account);

    await _setupForTASOrder(account, investment);
    await this.mettalexContract.tradeAtSettlement(positionToken.address, investment, {from: account});
    await _endTASOrder(account);
  };

  const _setupForUpdateSpot = async (account1, account2, collateral) => {
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, true, { from: owner });

    await _getCollateral(this.mettalexContract.address, collateral);
    await this.collateralToken.approve(this.mettalexContract.address, collateral, {from: account1});
    await this.collateralToken.approve(this.mettalexContract.address, collateral, {from: account2});
  };

  const _endUpdateSpot = async (account1, account2) => {
    await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });
    await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

    await this.collateralToken.approve(this.mettalexContract.address, 0, {from: account1});
    await this.collateralToken.approve(this.mettalexContract.address, 0, {from: account2});
  };

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
    const tokensToMint = 6;
    const requiredCollateral = new BN('15090000000000000');

    beforeEach(async () => {
      await _setupForMinting(user, requiredCollateral);
    });

    afterEach(async () => {
      await _endMinting(user);
    });

    after(async () => {
      await _setupForRedeeming(user, requiredCollateral);
      await this.mettalexContract.redeemPositionTokens(6, {from: user});
      await _endRedeeming(user);
    });
    
    // TO-DO: Complete upon implementation of settleContract in MettalexContract
    it('should reject mint if contract is settled');

    it('should reject mint from user if contract is not whitelisted in long position token', async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: other}), 'revert');
    });
    
    it('should reject mint from user if contract is not whitelisted in short position token', async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: other}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to insufficient collateral funds in user account', async () => {
      await _burnCollateral(user);

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: user}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToMint, {from: user}), 'revert');
    });

    it('should mint 6 long & 6 short position tokens', async () => {
      const receipt = await this.mettalexContract.mintPositionTokens(tokensToMint, {from: user});

      await expectEvent(receipt, 'LongPositionTokenMinted', {
        to: user,
        value: new BN(tokensToMint),
        collateralRequired: new BN('15000000000000000'),
        collateralFeeRequired: new BN('90000000000000'),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(tokensToMint);

      await expectEvent(receipt, 'ShortPositionTokenMinted', {
        to: user,
        value: new BN(tokensToMint),
        collateralRequired: new BN('15000000000000000'),
        collateralFeeRequired: new BN('90000000000000'),
      });

      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(tokensToMint);
    });
  });

  describe('Redeem position tokens', () => {
    const tokensToRedeem = 6;
    const requiredCollateral = new BN('15090000000000000');

    before(async () => {
      await _setupForMinting(user, requiredCollateral);
      await this.mettalexContract.mintPositionTokens(6, {from: user});
      await _endMinting(user);
    });

    beforeEach(async () => {
      await _setupForRedeeming(user, requiredCollateral);
    });

    afterEach(async () => {
      await _endRedeeming(user);
    });
  
    it('should revert if sender\'s address is invalid', async () => {
      await _getCollateral(this.mettalexContract.address, requiredCollateral);
      await expectRevert(this.mettalexContract.redeemPositionTokens(nullAddress, tokensToRedeem), 'INVALID_ADDRESS');
    });

    it('should revert if contract is not whitelisted in long position token', async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, { from: owner }), 'revert');
    });

    it('should revert if contract is not whitelisted in short position token', async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, { from: owner }), 'revert');
    });

    it('should revert if collateral cannot be transferred due to insufficient collateral funds in contract\'s collateral pool', async () => {
      await _burnCollateral(this.mettalexContract.address);

      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: user}), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.collateralToken.approve(this.mettalexContract.address, 0, {from: user});

      await expectRevert(this.mettalexContract.mintPositionTokens(tokensToRedeem, {from: user}), 'revert');
    });

    it('should revert if sender has insufficient tokens to redeem', async () => {
      await expectRevert(this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: other}), 'revert');
    });

    it('should revert if sender redeems more than total minted position tokens', async () => {
      await expectRevert(this.mettalexContract.redeemPositionTokens(7, {from: user}), 'revert');
    });

    it('should redeem 6 long and 6 short position tokens', async () => {
      const initialLongTokens = await this.longPositionToken.balanceOf(user);
      const initialShortTokens = await this.shortPositionToken.balanceOf(user);

      const receipt = await this.mettalexContract.redeemPositionTokens(tokensToRedeem, {from: user});
      await expectEvent(receipt, 'Redeem', {
        to: user,
        burntTokenQuantity: new BN(tokensToRedeem),
        collateralToReturn: new BN('15000000000000000'),
      });

      expect((await this.longPositionToken.balanceOf(user)).toNumber()).to.equal(initialLongTokens - tokensToRedeem);
      expect((await this.shortPositionToken.balanceOf(user)).toNumber()).to.equal(initialShortTokens - tokensToRedeem);
    });
  });

  describe('Trade at settlement', () => {
    const tokensToInvest = 2;

    before(async () => {
      await _setupForMinting(user, new BN('15090000000000000'));
      await this.mettalexContract.mintPositionTokens(3, {from: user});
      await _endMinting(user);
    });

    beforeEach(async () => {
      await _setupForTASOrder(user, tokensToInvest);
    });

    afterEach(async () => {
      await _endTASOrder(user);
    });

    after(async () => {
      await _setupForRedeeming(user, new BN('201200000000000000'));
      await this.mettalexContract.redeemPositionTokens(1, {from: user});
      await _endRedeeming(user);
    });

    it('should reject call without either of long or short token', async () => {
      await expectRevert(this.mettalexContract.tradeAtSettlement(other, tokensToInvest, {from: user}), 'Given address must be either of Long Position Token or Short Position Token');
    });

    it('should reject call if contract not approved to transfer long or short tokens', async () => {
      await _endTASOrder(user);

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
      await _setupForMinting(user, new BN('15090000000000000'));
      await this.mettalexContract.mintPositionTokens(3, {from: user});
      await _endMinting(user);
    });

    beforeEach(async () => {
      await _setupForUpdateSpot(user, user, requiredCollateral);
    });

    afterEach(async () => {
      await _endUpdateSpot(user, user);
    });

    after(async () => {
      await _setupForRedeeming(user, new BN('201200000000000000'));
      await this.mettalexContract.redeemPositionTokens(1, {from: user});
      await _endRedeeming(user);
    });
    
    it('should reject call from address other than price updater', async () => {
      await expectRevert(this.mettalexContract.updateSpot(20000000, {from: user}), 'ORACLE_ONLY');
    });

    it('should reject price update on breach', async () => {
      await expectRevert(this.mettalexContract.updateSpot(24000000, {from: oracle}), 'arbitration price must be within contract bounds');
    });

    it('should reject price update if contract is not whitelisted in long position token', async () => {
      await this.longPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.updateSpot(44000000, {from: oracle}), 'WHITELISTED_ONLY');
    });
  
    it('should reject price update if contract is not whitelisted in short position token', async () => {
      await this.shortPositionToken.setWhitelist(this.mettalexContract.address, false, { from: owner });

      await expectRevert(this.mettalexContract.updateSpot(44000000, {from: oracle}), 'WHITELISTED_ONLY');
    });

    it('should update spot price & deal with TAS orders', async () => {
      const initialLongTokens = await this.longPositionToken.balanceOf(this.mettalexContract.address);
      const initialShortTokens = await this.shortPositionToken.balanceOf(this.mettalexContract.address);
      const initialPriceUpdateCount = (await this.mettalexContract.priceUpdateCount()).toNumber();

      const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
      await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});

      expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialLongTokens - 2);
      expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toNumber()).to.equal(initialShortTokens - 2);

      expect((await this.mettalexContract.priceUpdateCount()).toNumber()).to.equal(initialPriceUpdateCount + 1);
    });

    it('should update spot price & not deal with TAS orders as neither long nor short TAS order exists', async () => {
      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialPriceUpdateCount = new BN((await this.mettalexContract.priceUpdateCount()).toString());

      const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
      await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});

      expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialLongTokens.toString());
      expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialShortTokens.toString());

      expect((await this.mettalexContract.priceUpdateCount()).toString()).to.equal(initialPriceUpdateCount.toString());
    });

    it('should update spot price & deal with only existing long TAS order', async () => {
      await _makeTASOrder(user3, this.longPositionToken, 2);

      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user3});

      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialPriceUpdateCount = new BN((await this.mettalexContract.priceUpdateCount()).toString());

      const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
      await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});

      expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialLongTokens.toString());
      expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialShortTokens.toString());
  
      expect((await this.mettalexContract.priceUpdateCount()).toString()).to.equal(initialPriceUpdateCount.toString());

      await _makeTASOrder(user5, this.shortPositionToken, 2);
      await _setupForUpdateSpot(user3, user5, requiredCollateral);
      await this.mettalexContract.updateSpot(44000000, {from: oracle});
    });
  
    it('should update spot price & deal with only existing short TAS order', async () => {
      await _makeTASOrder(user2, this.shortPositionToken, 2);

      await this.collateralToken.approve(this.mettalexContract.address, requiredCollateral, {from: user2});

      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString());
      const initialPriceUpdateCount = new BN((await this.mettalexContract.priceUpdateCount()).toString());

      const receipt = await this.mettalexContract.updateSpot(44000000, {from: oracle});
      await expectEvent(receipt, 'UpdatedLastPrice', {price: new BN(44000000)});

      expect((await this.longPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialLongTokens.toString());
      expect((await this.shortPositionToken.balanceOf(this.mettalexContract.address)).toString()).to.equal(initialShortTokens.toString());

      expect((await this.mettalexContract.priceUpdateCount()).toString()).to.equal(initialPriceUpdateCount.toString());

      await _makeTASOrder(user5, this.longPositionToken, 2);
      await _setupForUpdateSpot(user2, user5, requiredCollateral);
      await this.mettalexContract.updateSpot(44000000, {from: oracle});
    });
  });

  describe('Clear Settled Trade', () => {
    it('should revert as long TAS order\'s settle index is greater than price update count', async () => {
      await _makeTASOrder(user6, this.longPositionToken, 2);
      await this.collateralToken.approve(this.mettalexContract.address, new BN('5030000000000000'), {from: user6});

      await expectRevert(this.mettalexContract.clearLongSettledTrade({from: user6}), 'Can only clear previously settled order');
    });

    it('should revert as short TAS order\'s settle index is greater than price update count', async () => {
      await _makeTASOrder(user4, this.shortPositionToken, 2);
      await this.collateralToken.approve(this.mettalexContract.address, new BN('5030000000000000'), {from: user4});

      await expectRevert(this.mettalexContract.clearShortSettledTrade({from: user4}), 'Can only clear previously settled order');
    });

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

    it('should clear user\'s long position token investment having some contribution', async () => {
      await _makeTASOrder(user7, this.longPositionToken, 2);
      await _makeTASOrder(user7, this.shortPositionToken, 1);
      await _makeTASOrder(user2, this.longPositionToken, 2);
      await _setupForUpdateSpot(user4, user6, new BN('7545000000000000'));
      await this.mettalexContract.updateSpot(44000000, {from: oracle});

      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user7)).toString());
      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(user7)).toString());

      const receipt = await this.mettalexContract.clearLongSettledTrade({from: user7});

      await expectEvent(receipt, 'ClearedLongSettledTrade', {
        sender: user7,
        settledValue: new BN(0),
        senderContribution: new BN(1),
        senderExcess: new BN(1),
        positionQuantity: new BN(0),
        collateralQuantity: new BN(0),
      });

      expect((await this.collateralToken.balanceOf(user7)).toString()).to.equal(initialCollateralTokens.toString());
      expect((await this.longPositionToken.balanceOf(user7) - 1).toString()).to.equal(initialLongTokens.toString());
    });

    it('should clear user\'s short position token investment having some contribution', async () => {
      await _makeTASOrder(owner, this.longPositionToken, 1);
      await _makeTASOrder(owner, this.shortPositionToken, 2);
      await _setupForUpdateSpot(owner, owner, new BN('7545000000000000'));
      await this.mettalexContract.updateSpot(44000000, {from: oracle});

      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(owner)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(owner)).toString());

      const receipt = await this.mettalexContract.clearShortSettledTrade({
        from: owner
      });

      await expectEvent(receipt, 'ClearedShortSettledTrade', {
        sender: owner,
        settledValue: new BN(0),
        senderContribution: new BN(1),
        senderExcess: new BN(1),
        positionQuantity: new BN(0),
        collateralQuantity: new BN('0'),
      });

      expect((await this.collateralToken.balanceOf(owner)).toString()).to.equal((initialCollateralTokens).toString());
      expect((await this.shortPositionToken.balanceOf(owner) - 1).toString()).to.equal(initialShortTokens.toString());
    });

    it('should clear user\'s long position token investment having full contribution', async () => {
      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user6)).toString());
      const initialLongTokens = new BN((await this.longPositionToken.balanceOf(user6)).toString());

      const receipt = await this.mettalexContract.clearLongSettledTrade({from: user6});

      await expectEvent(receipt, 'ClearedLongSettledTrade', {
        sender: user6,
        settledValue: new BN(0),
        senderContribution: new BN(2),
        senderExcess: new BN(0),
        positionQuantity: new BN(0),
        collateralQuantity: new BN(0),
      });

      expect((await this.collateralToken.balanceOf(user6)).toString()).to.equal(initialCollateralTokens.toString());
      expect((await this.longPositionToken.balanceOf(user6)).toString()).to.equal(initialLongTokens.toString());
    });

    it('should clear user\'s short position token investment having full contribution', async () => {
      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user4)).toString());
      const initialShortTokens = new BN((await this.shortPositionToken.balanceOf(user4)).toString());

      const receipt = await this.mettalexContract.clearShortSettledTrade({
        from: user4
      });

      await expectEvent(receipt, 'ClearedShortSettledTrade', {
        sender: user4,
        settledValue: new BN(2),
        senderContribution: new BN(2),
        senderExcess: new BN(0),
        positionQuantity: new BN(1),
        collateralQuantity: new BN('2500000000000000'),
      });

      expect((await this.collateralToken.balanceOf(user4)).toString()).to.equal('2500000000000000');
      expect((await this.shortPositionToken.balanceOf(user4)).toString()).to.equal(initialShortTokens.toString());
    });

    it('should clear user\'s long position token investment having no contribution', async () => {
      const initialCollateralTokens = new BN((await this.collateralToken.balanceOf(user2)).toString());
      const initialLongTokens = (await this.longPositionToken.balanceOf(user2)).toNumber();

      const receipt = await this.mettalexContract.clearLongSettledTrade({from: user2});

      await expectEvent(receipt, 'ClearedLongSettledTrade', {
        sender: user2,
        settledValue: new BN(0),
        senderContribution: new BN(0),
        senderExcess: new BN(2),
        positionQuantity: new BN(0),
        collateralQuantity: new BN(0),
      });

      expect((await this.collateralToken.balanceOf(user2)).toString()).to.equal(initialCollateralTokens.toString());
      expect((await this.longPositionToken.balanceOf(user2)).toString()).to.equal((initialLongTokens + 2).toString());
    });

    it('should clear user\'s short position token investment having no contribution', async () => {
      await _makeTASOrder(other, this.longPositionToken, 1);
      await _makeTASOrder(other, this.shortPositionToken, 2);
      await _makeTASOrder(user3, this.shortPositionToken, 2);
      await _setupForUpdateSpot(other, other, new BN('2515000000000000'));
      await this.mettalexContract.updateSpot(44000000, {from: oracle});
      
      const initialCollateralTokens = (await this.collateralToken.balanceOf(user3)).toNumber();
      const initialShortTokens = (await this.shortPositionToken.balanceOf(user3)).toNumber();

      const receipt = await this.mettalexContract.clearShortSettledTrade({
        from: user3
      });

      await expectEvent(receipt, 'ClearedShortSettledTrade', {
        sender: user3,
        settledValue: new BN(0),
        senderContribution: new BN(0),
        senderExcess: new BN(2),
        positionQuantity: new BN(0),
        collateralQuantity: new BN(0),
      });

      expect((await this.collateralToken.balanceOf(user3)).toString()).to.equal(initialCollateralTokens.toString());
      expect((await this.shortPositionToken.balanceOf(user3)).toString()).to.equal((initialShortTokens + 2).toString());
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
