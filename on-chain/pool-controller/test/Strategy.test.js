const { expect } = require("chai");
const { accounts, contract } = require("@openzeppelin/test-environment");
const { BN, expectRevert, constants } = require("@openzeppelin/test-helpers");

// importing deployed contract addresses
const addresses = require("../../scripts/contract-cache/contract_cache.json");

// importing dependent contracts
const yVault = require("../../mettalex-yearn/build/contracts/yVault.json");
const yController = require("../../mettalex-yearn/build/contracts/Controller.json");
const WantFile = require("../../mettalex-vault/build/contracts/CoinToken.json");
const PositionFile = require("../../mettalex-vault/build/contracts/PositionToken.json");
const BPoolFile = require("../../mettalex-balancer/build/contracts/BPool.json");

// loading contract
const StrategyContract = contract.fromArtifact("StrategyBalancerMettalexV3");
const YContract = contract.fromABI(yVault.abi);
const YController = contract.fromABI(yController.abi);
const WantContract = contract.fromABI(WantFile.abi);
const LongContract = contract.fromABI(PositionFile.abi);
const ShortContract = contract.fromABI(PositionFile.abi);
const BPoolContract = contract.fromABI(BPoolFile.abi);

// defining user's account
const user = accounts[0];

// Starting test block
describe("Strategy", () => {
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

    // contract instances
    this.strategy = await StrategyContract.at(strategyAddress);
    this.yearn = await YContract.at(yearnControllerAddress);
    this.yController = await YController.at(yControllerAddress);
    this.want = await WantContract.at(wantAddress);
    this.long = await LongContract.at(longAddress);
    this.short = await ShortContract.at(shortAddress);
    this.bpool = await BPoolContract.at(BPoolAddress);

    // storing constructor defined addresses
    want = await this.strategy.want();
    balance = await this.strategy.balancer();
    mettalexVault = await this.strategy.mettalexVault();
    longToken = await this.strategy.longToken();
    shortToken = await this.strategy.shortToken();
    governance = await this.strategy.governance();
    controller = await this.strategy.controller();
  });

  // checking initial want balance for contract
  it("checking usdt balance for strategy contract to be 0", async () => {
    // asserting 0 balance
    expect(await this.strategy.balanceOf()).to.be.bignumber.equal("0");
  });

  // calling strategy deposit and withdraw public functions using non controller - false case
  it("calling deposit and withdraw with non-controller address should fail", async () => {
    // calling deposit should fail
    await expectRevert(
      this.strategy.deposit({ from: governance }),
      "!controller"
    );

    // calling withdraw should fail
    await expectRevert(
      this.strategy.withdraw(want, { from: governance }),
      "!controller"
    );
  });

  // calling withdraw for recovering mistaken tokens - false case
  it("should not allow to withdraw passing usdt/long/short as token address", async () => {
    // all calls should fails as tokens should not be want, long, short
    await expectRevert(
      this.strategy.withdraw(want, { from: controller }),
      "Want"
    );
    await expectRevert(
      this.strategy.withdraw(longToken, { from: controller }),
      "LTOK"
    );
    await expectRevert(
      this.strategy.withdraw(shortToken, { from: controller }),
      "STOK"
    );
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

  // checking minimum deposit value to be atleast 1000000 - false case
  it("test minimum deposit allowed", async () => {
    // depositing less than required
    await expectRevert(
      this.yearn.deposit(100000 * Math.pow(10, wDecimals), { from: user }),
      "SafeERC20: low-level call failed"
    );

    // depositing just less than required
    await expectRevert(
      this.yearn.deposit(999999 * Math.pow(10, wDecimals), { from: user }),
      "SafeERC20: low-level call failed"
    );
  });

  // testing a full deposit scenario
  it("user deposit scenario calling deposit and earn", async () => {
    amount = 1000000;

    depositAmount = amount * Math.pow(10, wDecimals);

    min = Number(await this.yearn.min());

    max = Number(await this.yearn.max());

    // value that would be sent to Pool Controller after reserving some USDT in yVault
    finalDeposit = (amount * Math.pow(10, wDecimals) * min) / max;

    // check usdt, long, short balance for strategy
    u = await this.want.balanceOf(addresses.BPool);
    l = await this.long.balanceOf(addresses.BPool);
    s = await this.short.balanceOf(addresses.BPool);

    // checking balances to be 0
    expect(u).to.be.bignumber.equal("0");
    expect(l).to.be.bignumber.equal("0");
    expect(s).to.be.bignumber.equal("0");

    // check total supply
    // expect(await this.strategy.supply()).to.be.bignumber.equal("0");

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

    // checking total supply
    // expect(await this.strategy.supply()).to.be.bignumber.equal(
    //   new BN(finalDeposit)
    // );

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
  });

  // testing boundings of tokens
  it("check positional tokens boundation", async () => {
    // checking bounding for long token
    expect(await this.strategy.isBound(longToken)).to.be.equal(true);

    // checking bounding for short token
    expect(await this.strategy.isBound(shortToken)).to.be.equal(true);
  });

  // checking swap fee
  it("checking swap fee to be a valid number", async () => {
    // get swap fee
    expect(await this.strategy.getSwapFee()).to.be.bignumber.above("0");
  });

  // should return a valid number > 0 for swap
  it("checking expected in amount by using lower value", async () => {
    x = await this.strategy.getExpectedInAmount(
      want,
      longToken,
      100 * Math.pow(10, lDecimals),
      { from: user }
    );
    expect(x[0]).to.be.bignumber.above("0");
    expect(x[1]).to.be.bignumber.above("0");
  });

  // To be Reviewed

  // should return a valid number > 0 for swap
  // it("checking expected in amount by using higher value", async () => {
  //   x = await this.strategy.getExpectedInAmount(
  //     want,
  //     longToken,
  //     10000 * Math.pow(10, lDecimals),
  //     { from: user }
  //   );
  //   expect(x[0]).to.be.bignumber.above("0");
  //   expect(x[1]).to.be.bignumber.above("0");
  // });

  // should return a valid number > 0 for swap
  it("checking expected out amount by using lower value", async () => {
    x = await this.strategy.getExpectedOutAmount(
      want,
      longToken,
      100 * Math.pow(10, lDecimals),
      { from: user }
    );
    expect(x[0]).to.be.bignumber.above("0");
    expect(x[1]).to.be.bignumber.above("0");
  });

  // should return a valid number > 0 for swap
  it("checking expected out amount by using higher value", async () => {
    x = await this.strategy.getExpectedOutAmount(
      want,
      longToken,
      10000 * Math.pow(10, lDecimals),
      { from: user }
    );
    expect(x[0]).to.be.bignumber.above("0");
    expect(x[1]).to.be.bignumber.above("0");
  });

  // trying swap functionality
  it("checking swap functionality", async () => {
    // checking expected out amount after swap
    x = await this.strategy.getExpectedOutAmount(
      want,
      longToken,
      100 * Math.pow(10, lDecimals),
      { from: user }
    );
    expect(x[0]).to.be.bignumber.above("0");
    expect(x[1]).to.be.bignumber.above("0");

    // get expected amount to be received
    x = await this.strategy.getExpectedOutAmount(
      want,
      longToken,
      1000 * Math.pow(10, wDecimals),
      { from: user }
    );

    // checking controller pool controller address
    expect(this.strategy.address).to.be.equal(addresses.PoolController);

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

  // implementing withdraw scenario
  it("withdraw less than vault balance scenario", async () => {
    // getting supply
    // supply = await this.strategy.supply();

    // checking no. of shares with user
    expect(await this.yearn.balanceOf(user)).to.be.bignumber.equal(
      new BN(depositAmount)
    );

    // defining withdraw amount
    withdraw = depositAmount / 5;

    // withdraw some usdt from strategy contract
    await this.yearn.withdraw(withdraw, { from: user });

    // checking no. of shares with user
    expect(await this.yearn.balanceOf(user)).to.be.bignumber.equal(
      new BN(depositAmount - withdraw)
    );

    // update user holding usdt amount
    depositAmount = depositAmount - withdraw;
  });

  // To be reviewed

  //  // implementing withdraw scenario
  //  it("full amount withdraw scenario", async () => {
  //     // getting new supply
  //     supply = await this.strategy.supply()

  //     // checking no. of shares with user
  //     expect(
  //       x = await this.yearn.balanceOf(user)
  //     ).to.be.bignumber.equal(new BN(depositAmount))

  //     // update withdraw amount
  //     withdraw = depositAmount

  //     // withdraw all usdt from strategy contract
  //     await this.yearn.withdraw(withdraw,{from : user})

  //     // checking no. of shares with user
  //     expect(
  //       await this.yearn.balanceOf(user)
  //     ).to.be.bignumber.equal(new BN('0'))
  //   })

  // calling full withdraw from yController
  it("calling full withdraw using governance proceeding with user withdraw", async () => {
    // checking no. of shares with user
    expect(await this.yearn.balanceOf(user)).to.be.bignumber.equal(
      new BN(depositAmount)
    );

    // withdraw all
    await this.yController.withdrawAll(want, { from: governance });

    // update withdraw amount
    withdraw = depositAmount / 2;

    // user balance
    wantBal = Number(await this.want.balanceOf(user));
    shareBal = Number(await this.yearn.balanceOf(user));
    // withdraw some usdt from strategy contract
    await this.yearn.withdraw(withdraw, { from: user });

    // checking no. of shares with user
    expect(await this.yearn.balanceOf(user)).to.be.bignumber.equal(
      new BN(shareBal - withdraw)
    );

    // To be reviewed

    // // checking user want balance
    // expect(
    //   await this.want.balanceOf(user)
    // ).to.be.bignumber.equal(new BN(wantBal + withdraw))

    // updating deposit amount
    depositAmount = depositAmount - withdraw;
  });

  // implementing withdraw scenario
  it("full amount withdraw scenario after governance withthdraws all usdt", async () => {
    // getting new supply
    // supply = await this.strategy.supply();

    // checking no. of shares with user
    expect((x = await this.yearn.balanceOf(user))).to.be.bignumber.equal(
      new BN(depositAmount)
    );

    // update withdraw amount
    withdraw = depositAmount;

    // withdraw all usdt from strategy contract
    await this.yearn.withdraw(withdraw, { from: user });

    // checking no. of shares with user
    expect(await this.yearn.balanceOf(user)).to.be.bignumber.equal(new BN("0"));
  });

  // updating swapFee
  it("updating swap fee", async () => {
    // get swap fee
    expect((x = await this.strategy.getSwapFee())).to.be.bignumber.above("0");

    // trying false case without governance
    await expectRevert(
      this.strategy.setSwapFee(new BN(100000 * Math.pow(10, wDecimals)), {
        from: user
      }),
      "!governance"
    );

    // trying false case
    await expectRevert(
      this.strategy.setSwapFee(new BN(100000 * Math.pow(10, wDecimals)), {
        from: user
      }),
      "!governance"
    );

    // trying false case
    await expectRevert(
      this.strategy.setSwapFee(new BN(100000 * Math.pow(10, wDecimals)), {
        from: governance
      }),
      "ERR_MIN_FEE"
    );

    // setting using governance
    await this.strategy.setSwapFee(new BN(2000000 * Math.pow(10, wDecimals)), {
      from: governance
    });

    // get swap fee
    expect((x = await this.strategy.getSwapFee())).to.be.bignumber.equal(
      new BN(2000000 * Math.pow(10, wDecimals))
    );
  });

  // checking setting of breaker using various accounts
  it("checking setting of breaker", async () => {
    // setting breaker through user should fail
    await expectRevert(
      this.strategy.setBreaker(true, { from: user }),
      "!governance"
    );

    // setting controller through controller should fail
    await expectRevert(
      this.strategy.setBreaker(true, { from: controller }),
      "!governance"
    );

    // setting controller through governance
    this.strategy.setBreaker(true, { from: governance });

    expect(await this.strategy.breaker()).to.be.equal(true);
  });

  // checking setting of controller address by various accounts
  it("checking to set a new controller", async () => {
    // setting controller through user should fail
    await expectRevert(
      this.strategy.setController(accounts[9], { from: user }),
      "!governance"
    );

    // setting controller through controller should fail
    await expectRevert(
      this.strategy.setController(accounts[9], { from: controller }),
      "!governance"
    );

    // setting controller through governance
    this.strategy.setController(accounts[9], { from: governance });

    expect(await this.strategy.controller()).to.be.equal(accounts[9]);
  });

  // checking setting of governanace using various accounts
  it("checking to set a new governance address", async () => {
    // setting controller through user should fail
    await expectRevert(
      this.strategy.setGovernance(accounts[9], { from: user }),
      "!governance"
    );

    // setting controller through controller should fail
    await expectRevert(
      this.strategy.setGovernance(accounts[9], { from: controller }),
      "!governance"
    );

    // setting governance through governance
    this.strategy.setGovernance(accounts[9], { from: governance });

    expect(await this.strategy.governance()).to.be.equal(accounts[9]);
  });
});
