const { expect } = require("chai");
const { accounts, contract, web3 } = require("@openzeppelin/test-environment");
const {
  BN,
  expectEvent,
  expectRevert,
  constants
} = require("@openzeppelin/test-helpers");
const addresses = require("../../scripts/contract-cache/contract_cache.json");
// console.log(addresses)
// importing dependent contracts
const yVault = require('../../mettalex-yearn/build/contracts/yVault.json');
const yController = require('../../mettalex-yearn/build/contracts/Controller.json');
const WantFile = require('../../mettalex-vault/build/contracts/CoinToken.json');
const PositionFile = require('../../mettalex-vault/build/contracts/PositionToken.json');
// const WANT = require('../../mettalex-yearn/build/contracts/Controller.json');
// const LONG = require('../../mettalex-yearn/build/contracts/Controller.json');
// const SHORT = require('../../mettalex-yearn/build/contracts/Controller.json');

// console.log(accounts)
const StrategyContract = contract.fromArtifact("StrategyBalancerMettalexV3");
const YContract = contract.fromABI(yVault.abi)
const YController = contract.fromABI(yController.abi)
const WantContract = contract.fromABI(WantFile.abi)
const LongContract = contract.fromABI(PositionFile.abi)
const ShortContract = contract.fromABI(PositionFile.abi)

// defining user
const user = accounts[0]

// Starting test block
describe("Strategy", () => {

  // initializing strategy contract using deployed address
  beforeEach(async () => {
    const strategyAddress = addresses.PoolController;
    const yearnControllerAddress = addresses.YVault;
    const yControllerAddress = addresses.YController;
    const wantAddress = addresses.Coin;
    const longAddress = addresses.Long;
    const shortAddress = addresses.Short;

    this.strategy = await StrategyContract.at(strategyAddress);
    this.yearn = await YContract.at(yearnControllerAddress);
    this.yController = await YController.at(yControllerAddress)
    this.want = await WantContract.at(wantAddress);
    this.long = await LongContract.at(longAddress);
    this.short = await ShortContract.at(shortAddress);
    // console.log(this.yearn)
    
    // storing constructor defined addresses
    want = await this.strategy.want();
    balance = await this.strategy.balancer();
    mettalexVault = await this.strategy.mettalexVault();
    longToken = await this.strategy.longToken();
    shortToken = await this.strategy.shortToken();
    governance = await this.strategy.governance();
    controller = await this.strategy.controller();
  });

  // checking want address
  it("checking usdt balance for strategy contract to be 0", async () => {
    expect(
      await this.strategy.balanceOf()
    ).to.be.bignumber.equal('0');
  });

  // calling stategy public functions using non controller - false case
  it("calling deposit and withdraw with non-controller address should fail", async () => {
    await expectRevert(
      this.strategy.deposit({ from: governance }),
      '!controller'
    );
    
    await expectRevert(
      this.strategy.withdraw(want, { from: governance }),
      '!controller'
    );
  });

  // calling withdraw for recovering mistaken tokens - false case
  it("should not allow to withdraw passing usdt/long/short as token address", async () => {
    await expectRevert(
      this.strategy.withdraw(want, { from: controller }),
      'Want'
    );
    await expectRevert(
      this.strategy.withdraw(longToken, { from: controller }),
      'LTOK'
    );
    await expectRevert(
      this.strategy.withdraw(shortToken, { from: controller }),
      'STOK'
    );
  });

  it("depositing usdt in user's account ", async () => {
    
    wDecimals = await this.want.decimals();
    lDecimals = await this.long.decimals();
    sDecimals = await this.short.decimals();
    // console.log("USDT D : ",Number(wDecimals)," LONG D : ",Number(lDecimals)," SHORT D : ",Number(sDecimals))

    // getting want owner address
    ownerAddress = await this.want.owner();

    // checking want owner balance greater than 0
    expect(
      await this.want.balanceOf(ownerAddress)
    ).to.be.bignumber.above('0')
    
    // transfer some usdt to user address for testing cases  

    expect(
      await this.want.balanceOf(user)
    ).to.be.bignumber.equal('0');

    // transferring 10000000 want tokens
    await this.want.transfer(user,10000000*Math.pow(10,wDecimals),{from : ownerAddress})
    
    expect(
      await this.want.balanceOf(user)
    ).to.be.bignumber.equal(new BN(10000000*Math.pow(10,wDecimals)));
    
  })

  // minimum deposit is atleast 1000000 - false case
  it("test minimum deposit allowed", async ()=>{
    // depositing less than required
    await expectRevert(
      this.yearn.deposit(100000*Math.pow(10,wDecimals),{from : user}),
      "SafeERC20: low-level call failed"
    )

    // depositing just less than required
    await expectRevert(
      this.yearn.deposit(999999*Math.pow(10,wDecimals),{from : user}),
      "SafeERC20: low-level call failed"
    )
  })

  // testing a full deposit scenario
  it("user deposit scenario calling deposit and earn", async () => {

    amount = 1000000

    depositAmount = amount*Math.pow(10,wDecimals);

    min = Number(await this.yearn.min())

    max = Number(await this.yearn.max())

    finalDeposit = amount*Math.pow(10,wDecimals)*min/max;
    
    // check usdt, long, short balance for strategy
    u = await this.want.balanceOf(addresses.BPool);
    l = await this.long.balanceOf(addresses.BPool);
    s = await this.short.balanceOf(addresses.BPool);

    // checking balances to be 0
    expect(u).to.be.bignumber.equal('0');
    expect(l).to.be.bignumber.equal('0');
    expect(s).to.be.bignumber.equal('0');

    // check total supply
    expect(
      await this.strategy.supply()
    ).to.be.bignumber.equal("0");

    // deposit some usdt to strategy contract
    expect(
      await this.yearn.address
    ).to.be.equal(addresses.YVault)

    // give allowance to vault contract
    await this.want.approve(addresses.YVault, depositAmount,{from : user});

    // checking allownace given
    expect( 
      await this.want.allowance(accounts[0],addresses.YVault)
    ).to.be.bignumber.equal(new BN(depositAmount))

    // check strategy usdt balance
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal('0');

    // checking strategies address for want
    expect(
      await this.yController.strategies(want)
    ).to.be.equal(addresses.PoolController);
  
    // call deposit function (Yearn)
    await this.yearn.deposit(depositAmount,{from : user})

    // checking balance of vault after deposit
    expect(
      await this.yearn.available()
    ).to.be.bignumber.equal(new BN(finalDeposit))

    // call earn to start movement of deposited amount together
    await this.yearn.earn({from : user})

    // checking total supply
    expect(
      await this.strategy.supply()
    ).to.be.bignumber.equal(new BN(finalDeposit))

    // pool controller usdt balance
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal('0')
    
    // yVault available balance
    expect(
      await this.want.balanceOf(addresses.YVault)
    ).to.be.bignumber.equal(new BN(depositAmount-finalDeposit))

    // bpool usdt balance
    expect(
      await this.want.balanceOf(addresses.BPool)
    ).to.be.bignumber.equal(new BN(finalDeposit/2))

    // check long,short balance -> should have increased
    expect(
      await this.short.balanceOf(addresses.BPool)
    ).to.be.bignumber.above("0");
    expect( 
      await this.long.balanceOf(addresses.BPool)
    ).to.be.bignumber.above("0");

  })

  // should return a valid number > 0 for swap
  it("checking expected in amount by using lower value", async () => {
    x = await this.strategy.getExpectedInAmount(want,longToken,100*Math.pow(10,lDecimals),{from : user});
    expect(x[0]).to.be.bignumber.above('0')
    expect(x[1]).to.be.bignumber.above('0')
  })

  // should return a valid number > 0 for swap
  it("checking expected in amount by using higher value", async () => {
    x = await this.strategy.getExpectedInAmount(want,longToken,10000*Math.pow(10,lDecimals),{from : user});
    expect(x[0]).to.be.bignumber.above('0')
    expect(x[1]).to.be.bignumber.above('0')
  })

  // implementing withdraw scenario 
  it("withdraw less than vault balance scenario", async () => {

   supply = await this.strategy.supply()

    // checking no. of shares with user
    expect(
      await this.yearn.balanceOf(user)
    ).to.be.bignumber.equal(new BN(depositAmount))

    withdraw = depositAmount/5

   // withdraw some usdt from strategy contract
   await this.yearn.withdraw(withdraw,{from : user})

   // checking no. of shares with user
   expect(
     await this.yearn.balanceOf(user)
   ).to.be.bignumber.equal(new BN(depositAmount-withdraw))

   depositAmount = depositAmount - withdraw

 })

  // implementing withdraw scenario 
  it("full amount withdraw scenario", async () => {
    
    supply = await this.strategy.supply()

     // checking no. of shares with user
     expect(
       await this.yearn.balanceOf(user)
     ).to.be.bignumber.equal(new BN(depositAmount))

     withdraw = depositAmount

    // withdraw some usdt from strategy contract
    await this.yearn.withdraw(withdraw,{from : user})

    // checking no. of shares with user
    expect(
      await this.yearn.balanceOf(user)
    ).to.be.bignumber.equal(new BN(depositAmount-withdraw))

  })

});
