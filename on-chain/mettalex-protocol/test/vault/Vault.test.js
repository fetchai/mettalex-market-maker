const { expect } = require("chai");
const { accounts, contract } = require("@openzeppelin/test-environment");
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

const Vault = contract.fromArtifact("Vault");
const CTK = contract.fromArtifact("TetherToken");
const PTK = contract.fromArtifact("PositionToken");

const [owner, oracle, amm, user, payee, newOracle, newAMM, other] = accounts;
const nullAddress = "0x0000000000000000000000000000000000000000";
const initVersion = "1";
const ctkDecimals = 6;
const ptkDecimals = 3;
const vaultName = "Mettalex Vault";
const cap = 3000000;
const floor = 2000000;
const multiplier = 10;
const feeRate = 300;
const ctkInitialSupply = 1000000000000;

describe("Vault", () => {
  beforeEach(async () => {
    this.ctk = await CTK.new(ctkInitialSupply, "Tether", "USDT", ctkDecimals, {
      from: other
    });
    this.long = await PTK.new("Long Token", "LTK", ptkDecimals, initVersion, {
      from: owner
    });
    this.short = await PTK.new("Short Token", "STK", ptkDecimals, initVersion, {
      from: owner
    });
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
    const remainingCTK = new BN((await this.ctk.balances(account)).toString());

    if (collateral.sub(remainingCTK) > new BN(0))
      await this.ctk.transfer(account, collateral.sub(remainingCTK), {
        from: other
      });
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

  describe("Check initializations", () => {
    it("should check contract name", async () => {
      expect((await this.vault.contractName()).toString()).to.equal(vaultName);
    });

    it("should check contract version", async () => {
      expect((await this.vault.version()).toString()).to.equal(initVersion);
    });

    it("should check spot price", async () => {
      expect((await this.vault.priceSpot()).toNumber()).to.equal(0);
    });

    it("should check cap", async () => {
      expect((await this.vault.priceCap()).toNumber()).to.equal(3000000);
    });

    it("should check floor", async () => {
      expect((await this.vault.priceFloor()).toNumber()).to.equal(2000000);
    });

    it("should check quantity multiplier", async () => {
      expect((await this.vault.qtyMultiplier()).toNumber()).to.equal(10);
    });

    it("should check collateral per unit", async () => {
      expect((await this.vault.collateralPerUnit()).toNumber()).to.equal(
        10000000
      );
    });

    it("should check collateral token fee per unit", async () => {
      expect((await this.vault.collateralFeePerUnit()).toNumber()).to.equal(
        75000
      );
    });

    it("should check settlement price", async () => {
      expect((await this.vault.settlementPrice()).toNumber()).to.equal(0);
    });

    it("should check fee accumulated", async () => {
      expect((await this.vault.feeAccumulated()).toNumber()).to.equal(0);
    });

    it("should check settlement timestamp", async () => {
      expect((await this.vault.settlementTimeStamp()).toNumber()).to.equal(0);
    });

    it("should check oracle", async () => {
      expect((await this.vault.oracle()).toString()).to.equal(oracle);
    });

    it("should check automated market maker", async () => {
      expect((await this.vault.ammPoolController()).toString()).to.equal(
        amm
      );
    });

    it("should check collateral token address", async () => {
      expect((await this.vault.collateralToken()).toString()).to.equal(
        this.ctk.address
      );
    });

    it("should check long token address", async () => {
      expect((await this.vault.longPositionToken()).toString()).to.equal(
        this.long.address
      );
    });

    it("should check short token address", async () => {
      expect((await this.vault.shortPositionToken()).toString()).to.equal(
        this.short.address
      );
    });

    it("should check owner address", async () => {
      expect((await this.vault.owner()).toString()).to.equal(owner);
    });
  });

  describe("Mint position tokens with quantity to mint", () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN("60450000000");

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
    });

    afterEach(async () => {
      await _afterTx(user);
    });

    it("should reject mint from user if contract is not whitelisted in long position token", async () => {
      await this.long.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(
        this.vault.mintPositions(tokenAmount, { from: other }),
        "revert"
      );
    });

    it("should reject mint from user if contract is not whitelisted in short position token", async () => {
      await this.short.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(
        this.vault.mintPositions(tokenAmount, { from: other }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to insufficient collateral funds in user account", async () => {
      const balanceCTK = await this.ctk.balances(user);
      await expectRevert(
        this.vault.mintPositions(balanceCTK + 1, { from: user }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user", async () => {
      await this.ctk.approve(this.vault.address, 0, { from: user });
      await expectRevert(
        this.vault.mintPositions(tokenAmount, { from: user }),
        "revert"
      );
    });

    it("should mint 6 long & 6 short position tokens", async () => {
      const receipt = await this.vault.mintPositions(tokenAmount, {
        from: user
      });
      expect((await this.long.balanceOf(user)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.vault.feeAccumulated()).toNumber()).to.equal(
        450000000
      );

      expectEvent(receipt, "PositionsMinted", {
        _to: user,
        _value: new BN(tokenAmount),
        _collateralRequired: new BN("60000000000"),
        _collateralFee: new BN("450000000")
      });
    });

    it("should charge 0 fee from automated market maker", async () => {
      await _beforeTx(amm, requiredCTK);
      const receipt = await this.vault.mintPositions(tokenAmount, {
        from: amm
      });
      expect((await this.long.balanceOf(amm)).toNumber()).to.equal(tokenAmount);
      expect((await this.short.balanceOf(amm)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.vault.feeAccumulated()).toNumber()).to.equal(0);

      expectEvent(receipt, "PositionsMinted", {
        _to: amm,
        _value: new BN(tokenAmount),
        _collateralRequired: new BN("60000000000"),
        _collateralFee: new BN("0")
      });
    });

    it("should reject mint if contract is settled", async () => {
      await this.vault.updateSpot(3000001, { from: oracle });
      await expectRevert(
        this.vault.mintPositions(tokenAmount, { from: user }),
        "revert"
      );
    });
  });

  describe("Mint position tokens with collateral amount", () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN("60450000000");

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
    });

    afterEach(async () => {
      await _afterTx(user);
    });

    it("should reject mint from user if contract is not whitelisted in long position token", async () => {
      await this.long.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(
        this.vault.mintFromCollateralAmount(requiredCTK, { from: other }),
        "revert"
      );
    });

    it("should reject mint from user if contract is not whitelisted in short position token", async () => {
      await this.short.setWhitelist(this.vault.address, false, { from: owner });
      await expectRevert(
        this.vault.mintFromCollateralAmount(requiredCTK, { from: other }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to insufficient collateral funds in user account", async () => {
      const balanceCTK = await this.ctk.balances(user);
      await expectRevert(
        this.vault.mintFromCollateralAmount(balanceCTK + 1, { from: user }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user", async () => {
      await this.ctk.approve(this.vault.address, 0, { from: user });
      await expectRevert(
        this.vault.mintFromCollateralAmount(requiredCTK, { from: user }),
        "revert"
      );
    });

    it("should mint 6 long & 6 short position tokens", async () => {
      const receipt = await this.vault.mintFromCollateralAmount(requiredCTK, {
        from: user
      });
      expect((await this.long.balanceOf(user)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.vault.feeAccumulated()).toNumber()).to.equal(
        450000000
      );

      expectEvent(receipt, "PositionsMinted", {
        _to: user,
        _value: new BN(tokenAmount),
        _collateralRequired: new BN("60000000000"),
        _collateralFee: new BN("450000000")
      });
    });

    it("should charge 0 fee from automated market maker", async () => {
      await _beforeTx(amm, requiredCTK);
      const receipt = await this.vault.mintFromCollateralAmount(60000000000, {
        from: amm
      });
      expect((await this.long.balanceOf(amm)).toNumber()).to.equal(tokenAmount);
      expect((await this.short.balanceOf(amm)).toNumber()).to.equal(
        tokenAmount
      );
      expect((await this.vault.feeAccumulated()).toNumber()).to.equal(0);

      expectEvent(receipt, "PositionsMinted", {
        _to: amm,
        _value: new BN(tokenAmount),
        _collateralRequired: new BN("60000000000"),
        _collateralFee: new BN("0")
      });
    });

    it("should reject mint if contract is settled", async () => {
      await this.vault.updateSpot(3000001, { from: oracle });
      await expectRevert(
        this.vault.mintFromCollateralAmount(tokenAmount, { from: user }),
        "revert"
      );
    });
  });

  describe("Redeem position tokens", () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN("60450000000");

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
      await this.vault.mintPositions(tokenAmount, { from: user });
    });

    afterEach(async () => {
      await _afterTx(user);
      const longBalance = await this.long.balanceOf(user);
      const shortBalance = await this.short.balanceOf(user);
      await this.long.burn(user, longBalance, { from: owner });
      await this.short.burn(user, shortBalance, { from: owner });
    });

    it("should revert if sender's address is invalid", async () => {
      await _getCollateral(this.vault.address, requiredCTK);
      await expectRevert(
        this.vault.redeemPositions(nullAddress, tokenAmount),
        "revert"
      );
    });

    it("should revert if contract is not whitelisted in long position token", async () => {
      await this.long.setWhitelist(this.vault.address, false, { from: owner });

      await expectRevert(
        this.vault.redeemPositions(tokenAmount, { from: owner }),
        "revert"
      );
    });

    it("should revert if contract is not whitelisted in short position token", async () => {
      await this.short.setWhitelist(this.vault.address, false, { from: owner });

      await expectRevert(
        this.vault.redeemPositions(tokenAmount, { from: owner }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to insufficient collateral funds in contract's collateral pool", async () => {
      await expectRevert(
        this.vault.redeemPositions(tokenAmount * 10, { from: user }),
        "revert"
      );
    });

    it("should revert if collateral cannot be transferred due to lack of approval to transfer collateral from user", async () => {
      await this.ctk.approve(this.vault.address, 0, { from: user });

      await expectRevert(
        this.vault.mintPositions(tokenAmount, { from: user }),
        "revert"
      );
    });

    it("should revert if sender has insufficient tokens to redeem", async () => {
      await expectRevert(
        this.vault.redeemPositions(tokenAmount, { from: other }),
        "revert"
      );
    });

    it("should revert if sender redeems more than total minted position tokens", async () => {
      await expectRevert(
        this.vault.redeemPositions(tokenAmount + 1, { from: user }),
        "revert"
      );
    });

    it("should redeem 6 long and 6 short position tokens", async () => {
      const initialLTK = await this.long.balanceOf(user);
      const initialSTK = await this.short.balanceOf(user);

      const receipt = await this.vault.redeemPositions(tokenAmount, {
        from: user
      });
      expectEvent(receipt, "PositionsRedeemed", {
        _to: user,
        _tokensBurned: new BN(tokenAmount),
        _collateralReturned: new BN("60000000000")
      });

      expect((await this.long.balanceOf(user)).toNumber()).to.equal(
        initialLTK - tokenAmount
      );
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(
        initialSTK - tokenAmount
      );
    });

    it("should be able to redeem if contract is settled", async () => {
      await this.vault.updateSpot(3000001, { from: oracle });
      const initialLTK = await this.long.balanceOf(user);
      const initialSTK = await this.short.balanceOf(user);
      const receipt = await this.vault.redeemPositions(tokenAmount, {
        from: user
      });

      expectEvent(receipt, "PositionsRedeemed", {
        _to: user,
        _tokensBurned: new BN(tokenAmount),
        _collateralReturned: new BN("60000000000")
      });

      expect((await this.long.balanceOf(user)).toNumber()).to.equal(
        initialLTK - tokenAmount
      );
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(
        initialSTK - tokenAmount
      );
    });
  });

  describe("Update spot", () => {
    const spotPrice = 2500000;
    const breachedSpot = 3000001;

    it("should reject call from address other than oracle", async () => {
      await expectRevert(
        this.vault.updateSpot(spotPrice, { from: user }),
        "ORACLE_ONLY"
      );
    });

    it("should update spot price", async () => {
      const receipt = await this.vault.updateSpot(spotPrice, { from: oracle });
      expectEvent(receipt, "UpdatedLastPrice", { _price: new BN(spotPrice) });
      expect((await this.vault.priceSpot()).toNumber()).to.equal(spotPrice);
    });

    it("should settle contract on breach", async () => {
      const receipt = await this.vault.updateSpot(breachedSpot, {
        from: oracle
      });

      expectEvent(receipt, "ContractSettled", {
        _settlePrice: new BN(breachedSpot)
      });

      expect(await this.vault.isSettled()).to.equal(true);
      expect((await this.vault.contractName()).toString()).to.equal(
        `${vaultName} (settled)`
      );
      expect((await this.vault.settlementPrice()).toNumber()).to.equal(
        breachedSpot
      );
    });

    it("should reject price update if contract is settled", async () => {
      await this.vault.updateSpot(breachedSpot, { from: oracle });
      await expectRevert(
        this.vault.updateSpot(spotPrice, { from: oracle }),
        "Contract is already settled"
      );
    });
  });

  describe("Claim fee", () => {
    const tokenAmount = 6000;
    const requiredCTK = new BN("60450000000");
    const expectedFee = 450000000;

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
      await this.vault.mintPositions(tokenAmount, { from: user });
    });

    it("should reject if not called by owner", async () => {
      await expectRevert(
        this.vault.claimFee(payee, { from: other }),
        "Ownable: caller is not the owner"
      );
    });

    it("should allow owner to claim accumulated fee", async () => {
      const initialCTK = await this.ctk.balances(this.vault.address);

      const receipt = await this.vault.claimFee(payee, { from: owner });
      expectEvent(receipt, "FeeClaimed", {
        _payee: payee,
        _weiAmount: new BN(expectedFee)
      });

      expect((await this.ctk.balances(this.vault.address)).toNumber()).to.equal(
        initialCTK - expectedFee
      );
      expect((await this.ctk.balances(payee)).toNumber()).to.equal(expectedFee);
    });
  });

  describe("Settle positions", () => {
    const tokenAmount = new BN("6000");
    const requiredCTK = new BN("60450000000");
    const collateralReturned = new BN("60000000000");
    const capBreached = 3000001;
    const floorBreached = 1999999;

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
      await this.vault.mintPositions(tokenAmount, { from: user });
    });

    afterEach(async () => {
      await _afterTx(user);
      const longBalance = await this.long.balanceOf(user);
      const shortBalance = await this.short.balanceOf(user);
      await this.long.burn(user, longBalance, { from: owner });
      await this.short.burn(user, shortBalance, { from: owner });
    });

    it("should reject if contract not settled", async () => {
      await expectRevert(
        this.vault.settlePositions({ from: user }),
        "Contract should be settled"
      );
    });

    it("should settle if cap breached", async () => {
      await this.vault.updateSpot(capBreached, { from: oracle });
      const initialCTK = await this.ctk.balances(this.vault.address);
      const receipt = await this.vault.settlePositions({ from: user });

      expectEvent(receipt, "PositionSettled", {
        _settler: user,
        _longTokensBurned: tokenAmount,
        _shortTokensBurned: tokenAmount,
        _collateralReturned: collateralReturned
      });

      expect((await this.ctk.balances(this.vault.address)).toNumber()).to.equal(
        initialCTK - collateralReturned
      );
      expect((await this.long.balanceOf(user)).toNumber()).to.equal(0);
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(0);
    });

    it("should settle if floor breached", async () => {
      await this.vault.updateSpot(floorBreached, { from: oracle });
      const initialCTK = await this.ctk.balances(this.vault.address);
      const receipt = await this.vault.settlePositions({ from: user });

      expectEvent(receipt, "PositionSettled", {
        _settler: user,
        _longTokensBurned: tokenAmount,
        _shortTokensBurned: tokenAmount,
        _collateralReturned: collateralReturned
      });

      expect((await this.ctk.balances(this.vault.address)).toNumber()).to.equal(
        initialCTK - collateralReturned
      );
      expect((await this.long.balanceOf(user)).toNumber()).to.equal(0);
      expect((await this.short.balanceOf(user)).toNumber()).to.equal(0);
    });
  });

  describe("Bulk settle positions", () => {
    const tokenAmount = new BN("6000");
    const requiredCTK = new BN("60450000000");
    const accounts120 = Array.from(Array(120), (_, i) => user);
    const accounts121 = Array.from(Array(121), (_, i) => user);

    const collateralReturned = new BN("60000000000");
    const breachedSpot = 3000001;

    beforeEach(async () => {
      await _beforeTx(user, requiredCTK);
      await this.vault.mintPositions(tokenAmount, { from: user });
    });

    afterEach(async () => {
      await _afterTx(user);
      const longBalance = await this.long.balanceOf(user);
      const shortBalance = await this.short.balanceOf(user);
      await this.long.burn(user, longBalance, { from: owner });
      await this.short.burn(user, shortBalance, { from: owner });
    });

    it("should reject if not called by owner", async () => {
      await expectRevert(
        this.vault.bulkSettlePositions(accounts, { from: other }),
        "Ownable: caller is not the owner"
      );
    });

    it("should reject if contract not settled", async () => {
      await expectRevert(
        this.vault.bulkSettlePositions(accounts, { from: owner }),
        "Contract should be settled"
      );
    });

    it("should reject if call exceeds max allowed length", async () => {
      await this.vault.updateSpot(breachedSpot, { from: oracle });
      await expectRevert(
        this.vault.bulkSettlePositions(accounts121, { from: owner }),
        " Cannot update more than 150 accounts"
      );
    });

    it("should settle for multiple addresses within max length", async () => {
      await this.vault.updateSpot(breachedSpot, { from: oracle });
      const initialCTK = await this.ctk.balances(this.vault.address);
      const receipt = await this.vault.bulkSettlePositions(accounts120, {
        from: owner
      });

      expectEvent(receipt, "PositionSettledInBulk", {
        _settlers: accounts120,
        _length: new BN(accounts120.length),
        _totalLongBurned: tokenAmount,
        _totalShortBurned: tokenAmount,
        _totalCollateralReturned: collateralReturned
      });

      expect((await this.ctk.balances(this.vault.address)).toNumber()).to.equal(
        initialCTK - collateralReturned
      );
    });
  });

  describe("Update oracle", () => {
    it("should reject if not called by owner", async () => {
      await expectRevert(
        this.vault.updateOracle(newOracle, { from: other }),
        "Ownable: caller is not the owner"
      );
    });

    it("should be able to update oracle", async () => {
      const receipt = await this.vault.updateOracle(newOracle, { from: owner });

      expectEvent(receipt, "OracleUpdated", {
        _previousOracle: oracle,
        _newOracle: newOracle
      });
      expect((await this.vault.oracle()).toString()).to.equal(newOracle);
    });
  });

  describe("Update AMM pool controller ", () => {
    it("should reject if not called by owner", async () => {
      await expectRevert(
        this.vault.updateAMMPoolController(newAMM, { from: other }),
        "Ownable: caller is not the owner"
      );
    });

    it("should be able to update oracle", async () => {
      const receipt = await this.vault.updateAMMPoolController(newAMM, {
        from: owner
      });

      expectEvent(receipt, "AMMPoolControllerUpdated", {
        _previousAMMPoolController: amm,
        _newAMMPoolController: newAMM
      });
      expect((await this.vault.ammPoolController()).toString()).to.equal(
        newAMM
      );
    });
  });
});
