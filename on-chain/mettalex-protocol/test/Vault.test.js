const { expect } = require('chai');
const { accounts, contract } = require('@openzeppelin/test-environment');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

const Vault = contract.fromArtifact('Vault');
const CTK = contract.fromArtifact('CoinToken');
const PTK = contract.fromArtifact('PositionToken');

const [owner, oracle, amm, user, other] = accounts;
const nullAddress = '0x0000000000000000000000000000000000000000';
const initVersion = 1;
const ctkDecimals = 6;
const ptkDecimals = 3;
const vaultName = 'Mettalex Vault';
const cap = 3000000;
const floor = 2000000;
const multiplier = 10;
const feeRate = 300;

describe('Vault', () => {
  before(async () => {
    this.ctk = await CTK.new('Tether', 'USDT', ctkDecimals, { from: other });
    this.long = await PTK.new('Long Token', 'LTK', ptkDecimals, initVersion, { from: owner });
    this.short = await PTK.new('Short Token', 'STK', ptkDecimals, initVersion, { from: owner });
    this.vault = await Vault.new(
      vaultName,
      initVersion,
      this.ctk.address,
      this.long.address,
      this.short.address,
      oracle,
      amm,
      cap,
      floor,
      multiplier,
      feeRate,
      { from: owner }
    );
  });

  const _getCollateral = async (account, collateral) => {
    const remainingCTK = new BN((await this.ctk.balanceOf(account)).toString());

    if (collateral.sub(remainingCTK) > new BN(0))
      await this.ctk.transfer(account, collateral.sub(remainingCTK), { from: owner });
  };

  const _whitelistVault = async () => {
    await this.long.setWhitelist(this.vault.address, true, { from: owner });
    await this.short.setWhitelist(this.vault.address, true, { from: owner });
  };

  const _blacklistVault = async () => {
    await this.long.setWhitelist(this.vault.address, false, { from: owner });
    await this.short.setWhitelist(this.vault.address, false, { from: owner });
  };

  const _beforeTx = async (account, collateral) => {
    await _whitelistVault();
    await this.ctk.transfer(account, collateral, { from: other });
    await this.ctk.approve(this.vault.address, collateral, { from: account });
  };

  const _afterTx = async (account) => {
    await _blacklistVault();
    await this.ctk.approve(this.vault.address, 0, { from: account });
  };

  describe('Check initializations', () => {
    it('should check contract name', async () => {
      expect((await this.vault.CONTRACT_NAME()).toString()).to.equal(vaultName);
    });

    it('should check spot price', async () => {
      expect((await this.vault.PRICE_SPOT()).toNumber()).to.equal(0);
    });

    it('should check cap', async () => {
      expect((await this.vault.PRICE_CAP()).toNumber()).to.equal(3000000);
    });

    it('should check floor', async () => {
      expect((await this.vault.PRICE_FLOOR()).toNumber()).to.equal(2000000);
    });

    it('should check quantity multiplier', async () => {
      expect((await this.vault.QTY_MULTIPLIER()).toNumber()).to.equal(10);
    });

    it('should check collateral per unit', async () => {
      expect((await this.vault.COLLATERAL_PER_UNIT()).toNumber()).to.equal(10000000);
    });

    it('should check collateral token fee per unit', async () => {
      expect((await this.vault.COLLATERAL_TOKEN_FEE_PER_UNIT()).toNumber()).to.equal(75000);
    });

    it('should check settlement price', async () => {
      expect((await this.vault.settlementPrice()).toNumber()).to.equal(0);
    });

    it('should check oracle', async () => {
      expect((await this.vault.ORACLE_ADDRESS()).toString()).to.equal(oracle);
    });
  });

  describe('Mint position tokens', () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN('60450000000');

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
    });

    afterEach(async () => {
      await _afterTx(user);
    });

    it('should reject mint if contract is settled');

    it('should reject mint from user if contract is not whitelisted in long position token', async () => {
      await this.long.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(this.vault.mintPositions(tokenAmount, { from: other }), 'revert');
    });

    it('should reject mint from user if contract is not whitelisted in short position token', async () => {
      await this.short.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(this.vault.mintPositions(tokenAmount, { from: other }), 'revert');
    });

    it('should revert if collateral cannot be transferred due to insufficient collateral funds in user account', async () => {
      const balanceCTK = await this.ctk.balanceOf(user);
      await expectRevert(this.vault.mintPositions(balanceCTK + 1, { from: user }), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.ctk.approve(this.vault.address, 0, { from: user });
      await expectRevert(this.vault.mintPositions(tokenAmount, { from: user }), 'revert');
    });

    it('should mint 6 long & 6 short position tokens', async () => {
      const receipt = await this.vault.mintPositions(tokenAmount, { from: user });
      expect((await this.long.balanceOf(user)).toNumber()).to.equal(tokenAmount);
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(tokenAmount);

      expectEvent(receipt, 'PositionsMinted', {
        to: user,
        value: new BN(tokenAmount),
        collateralRequired: new BN('60000000000'),
        collateralFee: new BN('450000000'),
      });
    });
  });

  describe('Redeem position tokens', () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN('60450000000');

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
    });

    afterEach(async () => {
      await _afterTx(user);
    });

    it("should revert if sender's address is invalid", async () => {
      await _getCollateral(this.vault.address, requiredCTK);
      await expectRevert(this.vault.redeemPositions(nullAddress, tokenAmount), 'revert');
    });

    it('should revert if contract is not whitelisted in long position token', async () => {
      await this.long.setWhitelist(this.vault.address, false, {
        from: owner,
      });

      await expectRevert(this.vault.redeemPositions(tokenAmount, { from: owner }), 'revert');
    });

    it('should revert if contract is not whitelisted in short position token', async () => {
      await this.short.setWhitelist(this.vault.address, false, {
        from: owner,
      });

      await expectRevert(this.vault.redeemPositions(tokenAmount, { from: owner }), 'revert');
    });

    it("should revert if collateral cannot be transferred due to insufficient collateral funds in contract's collateral pool", async () => {
      await expectRevert(this.vault.redeemPositions(tokenAmount * 10, { from: user }), 'revert');
    });

    it('should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user', async () => {
      await this.ctk.approve(this.vault.address, 0, { from: user });

      await expectRevert(this.vault.mintPositions(tokenAmount, { from: user }), 'revert');
    });

    it('should revert if sender has insufficient tokens to redeem', async () => {
      await expectRevert(this.vault.redeemPositions(tokenAmount, { from: other }), 'revert');
    });

    it('should revert if sender redeems more than total minted position tokens', async () => {
      await expectRevert(this.vault.redeemPositions(tokenAmount + 1, { from: user }), 'revert');
    });

    it('should redeem 6 long and 6 short position tokens', async () => {
      const initialLTK = await this.long.balanceOf(user);
      const initialSTK = await this.short.balanceOf(user);

      const receipt = await this.vault.redeemPositions(tokenAmount, { from: user });
      expectEvent(receipt, 'PositionsRedeemed', {
        to: user,
        tokensBurned: new BN(tokenAmount),
        collateralReturned: new BN('60000000000'),
      });

      expect((await this.long.balanceOf(user)).toNumber()).to.equal(initialLTK - tokenAmount);
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(initialSTK - tokenAmount);
    });
  });

  describe('updateSpot', () => {
    const spotPrice = 2500000;

    it('should reject call from address other than price updater', async () => {
      await expectRevert(this.vault.updateSpot(spotPrice, { from: user }), 'ORACLE_ONLY');
    });

    // it('should reject price update on breach', async () => {
    //   await expectRevert(
    //     this.vault.updateSpot(24000000, { from: oracle }),
    //     'arbitration price must be within contract bounds'
    //   );
    // });

    it('should update spot price', async () => {
      const receipt = await this.vault.updateSpot(spotPrice, { from: oracle });
      expectEvent(receipt, 'UpdatedLastPrice', { price: new BN(spotPrice) });
      expect((await this.vault.PRICE_SPOT()).toNumber()).to.equal(spotPrice);
    });
  });
});
