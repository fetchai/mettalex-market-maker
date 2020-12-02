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
const WantFile = require('../../mettalex-vault/build/contracts/CoinToken.json');
const PositionFile = require('../../mettalex-vault/build/contracts/PositionToken.json');
// const WANT = require('../../mettalex-yearn/build/contracts/Controller.json');
// const LONG = require('../../mettalex-yearn/build/contracts/Controller.json');
// const SHORT = require('../../mettalex-yearn/build/contracts/Controller.json');

console.log(accounts)
const StrategyContract = contract.fromArtifact("StrategyBalancerMettalexV3");
const YContract = contract.fromABI(yVault.abi)
const WantContract = contract.fromABI(WantFile.abi)
const LongContract = contract.fromABI(PositionFile.abi)
const ShortContract = contract.fromABI(PositionFile.abi)


// Starting test block
describe("Strategy", () => {

  // initializing strategy contract using deployed address
  beforeEach(async () => {
    const strategyAddress = addresses.PoolController;
    const yearnControllerAddress = addresses.YVault;
    const wantAddress = addresses.Coin;
    const longAddress = addresses.Long;
    const shortAddress = addresses.Short;

    this.strategy = await StrategyContract.at(strategyAddress);
    this.yearn = await YContract.at(yearnControllerAddress);
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

  it("calling deposit and withdraw with non-controller address should fail", async () => {
    await expectRevert(
      this.strategy.deposit({ from: governance }),
      '!controller'
    );

    // problem : withdraw(unit256) function is not getting called, defaults to withdraw(address)

    // await expectRevert(
    //   this.strategy.withdraw(new BN(1), { from: governance }),
    //   '!controller'
    // );
    
    await expectRevert(
      this.strategy.withdraw(want, { from: governance }),
      '!controller'
    );
  });

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

  it("trials ", async () => {
    
    wDecimals = await this.want.decimals();
    lDecimals = await this.long.decimals();
    sDecimals = await this.short.decimals();
    // console.log("USDT D : ",Number(wDecimals)," LONG D : ",Number(lDecimals)," SHORT D : ",Number(sDecimals))

    ownerAddress = await this.want.owner();

    console.log("WANT owner address -->",ownerAddress)
    console.log("Controller address -->",controller)

    bal = await this.want.balanceOf(ownerAddress);
    console.log("Onwer want balance",Number(bal))

    // transfer some usdt to user address for testing cases  

    user1 = accounts[0]
    console.log("Controller want balance",Number(await this.want.balanceOf(controller)))
    await this.want.transfer(controller,1000*Math.pow(10,wDecimals),{from : ownerAddress})
    console.log(Number(await this.want.balanceOf(controller)))
    
    // getting eth balance for owner and controller
    web3.eth.getBalance(ownerAddress).then((x)=>{console.log("owner eth bal : ",x)});
    web3.eth.getBalance(controller).then((x)=>{console.log("controller eth bal : ",x)});

    // transferring eth from owner to controller
    await web3.eth.sendTransaction({from:ownerAddress, to:controller, value: '1000000000000000'});
    
    web3.eth.getBalance(ownerAddress).then((x)=>{console.log("owner eth bal : ",x)});
    web3.eth.getBalance(controller).then((x)=>{console.log("controller eth bal : ",x)});
    console.log("------>")
  })

  // it("deposit scenario calling earn", async () => {
    
  //   // check usdt, long, short balance
  //   u = await this.want.balanceOf(controller);
  //   l = await this.long.balanceOf(controller);
  //   s = await this.short.balanceOf(controller);
  //   // console.log("USDT : ",Number(u)," LONG : ",Number(l)," SHORT : ",Number(s))

  //   // check total supply
  //   expect(
  //     await this.strategy.supply()
  //   ).to.be.bignumber.equal("0");
  //   // console.log(Number(ts))

  //   // deposit some usdt to strategy contract
  //   expect(
  //     await this.yearn.address
  //   ).to.be.equal(addresses.YController)
  //   await this.want.approve(addresses.YController, 1000*Math.pow(10,wDecimals),{from : accounts[0]});

  //   expect( 
  //     await this.want.allowance(accounts[0],addresses.YVault)
  //   ).to.be.bignumber.equal(new BN(1000*Math.pow(10,wDecimals)))

  //   // check strategy usdt balance
  //   expect(
  //     await this.want.balanceOf(addresses.PoolController)
  //   ).to.be.bignumber.equal('0');

  //   // call deposit function (Yearn)
  //   await this.yearn.deposit(1000*Math.pow(10,wDecimals),{from : accounts[0]})

  //   // check usdt balance -> should be half from earlier
  //   expect(
  //     await this.want.balanceOf(addresses.PoolController)
  //   ).to.be.bignumber.equal(new BN(500*Math.pow(10,wDecimals)));
    
  //   // check long,short balance -> should have increased
  //   expect(
  //     await this.short.balanceOf(controller)
  //   ).to.be.bignumber.above("0");
  //   expect( 
  //     await this.long.balanceOf(controller)
  //   ).to.be.bignumber.above("0");

  //   // total supply + -> oldUSDT-newUSDT
  //   expect(
  //     await this.strategy.supply()
  //   ).to.be.bignumber.equal(new BN(500*Math.pow(10,wDecimals)));

  // })


  it("deposit scenario calling direct deposit from Strategy", async () => {
    
    // check usdt, long, short balance
    u = await this.want.balanceOf(controller);
    l = await this.long.balanceOf(controller);
    s = await this.short.balanceOf(controller);
    // console.log("USDT : ",Number(u)," LONG : ",Number(l)," SHORT : ",Number(s))

    // check strategy usdt balance
    
    const wantBalance = Number(await this.want.balanceOf(addresses.PoolController));

    // call deposit function (Strategy) - should fail not controller
    expectRevert(
      this.strategy.deposit({from : accounts[0]}),
      '!controller'
    );
    console.log(controller)
    // controller deposits some usdt
    await this.want.transfer(addresses.PoolController,100*Math.pow(10,wDecimals),{from : controller})

    // this call should work
    await this.strategy.deposit({from : controller});

    // check usdt balance -> should be half from earlier
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal(new BN(wantBalance/2));
    
    // check long,short balance -> should have increased
    expect(
      await this.short.balanceOf(controller)
    ).to.be.bignumber.above(s);
    expect( 
      await this.long.balanceOf(controller)
    ).to.be.bignumber.above(s);

    // total supply + -> oldUSDT-newUSDT
    expect(
      await this.strategy.supply()
    ).to.be.bignumber.equal(new BN(500*Math.pow(10,wDecimals)));

  })


  it("withdraw scenario", async () => {
    
     // check usdt, long, short balance
     u = await this.want.balanceOf(controller);
     l = await this.long.balanceOf(controller);
     s = await this.short.balanceOf(controller);

     // check total supply
     expect(
       await this.strategy.supply()
     ).to.be.bignumber.equal("0");

    // withdraw some usdt from strategy contract
    this.yearn.withdraw(want,200*Math.pow(10,wDecimals),{from : user})

    // check usdt balance -> should be half from earlier
    expect(
      await this.want.balanceOf(addresses.PoolController)
    ).to.be.bignumber.equal(new BN(Number(u)/2));


    // check long,short balance -> should have increased
    expect(
      await this.short.balanceOf(controller)
    ).to.be.bignumber.above(s);
    expect( 
      await this.long.balanceOf(controller)
    ).to.be.bignumber.above(s);
  })

  it("checking expected in amount", async () => {
    x = await this.strategy.getExpectedInAmount(want,longToken,10000*Math.pow(10,5));
    console.log("--->",Number(x))
  })

});
