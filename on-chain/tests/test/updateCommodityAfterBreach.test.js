const { expect } = require("chai");
const { accounts, contract } = require("@openzeppelin/test-environment");
const { BN, expectRevert, constants } = require("@openzeppelin/test-helpers");

// importing deployed contract addresses
const addresses = require("../../scripts/contract-cache/contract_cache.json");

// importing dependent contracts
const strategy = require("../../pool-controller/build/contracts/StrategyBalancerMettalexV3.json");
const yVault = require("../../mettalex-yearn/build/contracts/yVault.json");
const yController = require("../../mettalex-yearn/build/contracts/Controller.json");
const WantFile = require("../../mettalex-vault/build/contracts/CoinToken.json");
const PositionFile = require("../../mettalex-vault/build/contracts/PositionToken.json");
const BPoolFile = require("../../mettalex-balancer/build/contracts/BPool.json");
const VaultFile = require("../../mettalex-vault/build/contracts/Vault.json");

var newContracts = {
  stk: {},
  ltk: {},
  vault: {}
}


// loading contract
const StrategyContract = contract.fromABI(strategy.abi);
const YContract = contract.fromABI(yVault.abi);
const YController = contract.fromABI(yController.abi);
const WantContract = contract.fromABI(WantFile.abi);
const LongContract = contract.fromABI(PositionFile.abi, PositionFile.bytecode);
const ShortContract = contract.fromABI(PositionFile.abi, PositionFile.bytecode);
const BPoolContract = contract.fromABI(BPoolFile.abi);
const VaultContract = contract.fromABI(VaultFile.abi,VaultFile.bytecode);

// defining user's account
const user = accounts[0];

// Starting test block
describe("UpdateCommodityAfterBreach", () => {
  // initializing contracts using deployed address
  beforeEach(async () => {
    // contract addresses
    const strategyAddress = addresses.PoolController;
    const yearnControllerAddress = addresses.YVault;
    const yControllerAddress = addresses.YController;
    const wantAddress = addresses.Coin;
    const longAddress = addresses.Long;
    const shortAddress = addresses.Short;
    const BPoolAddress = addresses.BPool;
    const VaultAddress = addresses.Vault;

    // contract instances
    this.strategy = await StrategyContract.at(strategyAddress);
    this.yearn = await YContract.at(yearnControllerAddress);
    this.yController = await YController.at(yControllerAddress);
    this.want = await WantContract.at(wantAddress);
    this.long = await LongContract.at(longAddress);
    this.short = await ShortContract.at(shortAddress);
    this.bpool = await BPoolContract.at(BPoolAddress);
    this.vault = await VaultContract.at(VaultAddress);

    //  storing constructor defined addresses
    want = await this.strategy.want();
    balance = await this.strategy.balancer();
    mettalexVault = await this.strategy.mettalexVault();
    longToken = await this.strategy.longToken();
    shortToken = await this.strategy.shortToken();
    governance = await this.strategy.governance();
    controller = await this.strategy.controller();
  });

  // transferring usdt balance from want contract owner address to user
  it("depositing usdt in user's account ", async () => {
    // initializing token decimals
    wDecimals = await this.want.decimals();
    lDecimals = await this.long.decimals();
    sDecimals = await this.short.decimals();

    // getting want owner address
    ownerAddress = await this.want.owner();

    // checking want owner balance greater than 0
    expect(await this.want.balanceOf(ownerAddress)).to.be.bignumber.above("0");

    // checking user want balance equal to 0
    expect(await this.want.balanceOf(user)).to.be.bignumber.equal("0");

    // transferring 1000000000 want tokens from want owner to user
    await this.want.transfer(user, 1000000000 * Math.pow(10, wDecimals), {
      from: ownerAddress
    });

    // confirming balance transferred to user
    expect(await this.want.balanceOf(user)).to.be.bignumber.equal(
      new BN(1000000000 * Math.pow(10, wDecimals))
    );
  });

  it("user deposits liquidity in the pool", async () => {
    amount = 20000;

    wDecimals = await this.want.decimals();

    depositAmount = amount * Math.pow(10, wDecimals);

    min = Number(await this.yearn.min());

    max = Number(await this.yearn.max());
    bal = await this.want.balanceOf(user) 
    // console.log(bal.toString());
    // console.log(user);

    // value that is sent to Pool Controller after reserving some USDT in yVault
    finalDeposit = (amount * Math.pow(10, wDecimals) * min) / max;

    // check usdt, long, short balance for strategy
    u = await this.want.balanceOf(addresses.BPool);
    l = await this.long.balanceOf(addresses.BPool);
    s = await this.short.balanceOf(addresses.BPool);

    // checking yVault address with contract address deployed
    expect(await this.yearn.address).to.be.equal(addresses.YVault);

    // give allowance to vault contract
    await this.want.approve(addresses.YVault, depositAmount, { from: user });

    // checking allownace given
    expect(
      await this.want.allowance(accounts[0], addresses.YVault)
    ).to.be.bignumber.equal(new BN(depositAmount));

    // check strategy usdt balance
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal("0");

    // checking strategies address mapped for want
    expect(await this.yController.strategies(want)).to.be.equal(
      addresses.PoolController
    );

    // call deposit function (Yearn)
    await this.yearn.deposit(depositAmount, { from: user });

    // checking balance of vault after deposit
    expect(await this.yearn.available()).to.be.bignumber.equal(
      new BN(finalDeposit)
    );

    // call earn to start movement of deposited amount together
    await this.yearn.earn({ from: user });

    // pool controller usdt balance
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal("0");

    // yVault available balance
    expect(await this.want.balanceOf(addresses.YVault)).to.be.bignumber.equal(
      new BN(depositAmount - finalDeposit)
    );

    // bpool usdt balance
    expect(await this.want.balanceOf(addresses.BPool)).to.be.bignumber.equal(
      new BN(finalDeposit / 2)
    );

    // check long,short balance -> should have increased
    expect(await this.short.balanceOf(addresses.BPool)).to.be.bignumber.above(
      "0"
    );
    expect(await this.long.balanceOf(addresses.BPool)).to.be.bignumber.above(
      "0"
    );
    // checking bounding for long token
    expect(await this.strategy.isBound(longToken)).to.be.equal(true);

    // checking bounding for short token
    expect(await this.strategy.isBound(shortToken)).to.be.equal(true);
  });

  it("create imbalance (buy L tokens)", async () => {
    x = await this.strategy.getExpectedOutAmount(
      want,
      longToken,
      1000 * Math.pow(10, wDecimals),
      { from: user }
    );

    // approving usdt to strategy contract
    await this.want.approve(
      addresses.PoolController,
      1000 * Math.pow(10, wDecimals),
      { from: user }
    );

    // defining max value
    MAX_UINT_VALUE = constants.MAX_UINT256;

    // swapping usdt with long
    await this.strategy.swapExactAmountIn(
      want,
      1000 * Math.pow(10, wDecimals),
      longToken,
      1,
      MAX_UINT_VALUE,
      { from: user }
    );

    // checking long tokens received amount
    expect(
      (longBalance = await this.long.balanceOf(user))
    ).to.be.bignumber.equal(x[0]);
  });

  it("breach commodity", async () => {
    //cap 3000, floor 2000
    const breachedSpot = 4500;
    oracle = await this.vault.oracle();
    await this.vault.updateSpot(breachedSpot, {from: oracle});
    expect(Number(await this.vault.settlementPrice()))
      .to.be.equal(Number(breachedSpot));
    expect(await this.vault.isSettled()).to.equal(true);
  });

  it("deploy contracts, set whitelist", async () => {
    ltk_name = await this.long.name();
    ltk_symbol = await this.long.symbol();
    ltk_decimals = await this.long.decimals();
    ltk_version = await this.long.version();
    const new_ltk = await LongContract.new(ltk_name, ltk_symbol, ltk_decimals, ltk_version);

    stk_name = await this.short.name();
    stk_symbol = await this.short.symbol();
    stk_decimals = await this.short.decimals();
    stk_version = await this.short.version();
    const new_stk = await LongContract.new(stk_name, stk_symbol, stk_decimals, stk_version);
    
    contractName = await this.vault.contractName();
    version = await this.vault.version();
    collateralToken = await this.vault.collateralToken();
    oracle = await this.vault.oracle();
    strategy_address = await this.vault.ammPoolController();

    const new_vault = await VaultContract.new(contractName, 1, collateralToken, new_ltk.address, new_stk.address,
      user, strategy_address, 5000, 4000, 1, 1);
    
    owner=await new_vault.owner();
    await new_ltk.setWhitelist(new_vault.address, true, { from: owner });
    await new_stk.setWhitelist(new_vault.address, true, { from: owner });

    newContracts.stk = new_stk
    newContracts.ltk = new_ltk
    newContracts.vault = new_vault
  });
  
  it("Update Spot, Handle breach and Update Commodity After Breach", async () => {
    //update spot
    oracle = await newContracts.vault.oracle();
    await newContracts.vault.updateSpot(4500,{
      from: oracle
    });

    //handle breach
    await this.strategy.handleBreach();
    expect(await this.strategy.isBreachHandled()).to.equal(true);
    
    //updateCommodityAfterBreach
    x = await this.strategy.updateCommodityAfterBreach(
      newContracts.vault.address, newContracts.ltk.address, newContracts.stk.address,
      {from: governance}
      );
  });
});