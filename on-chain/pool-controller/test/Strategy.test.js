const { expect } = require("chai");
const { accounts, contract } = require("@openzeppelin/test-environment");
const {
  BN,
  expectEvent,
  expectRevert,
  constants
} = require("@openzeppelin/test-helpers");
const addresses = require("../../scripts/contract-cache/contract_cache.json");

const StrategyContract = contract.fromArtifact("StrategyBalancerMettalexV2");

describe("Strategy", () => {
  beforeEach(async () => {
    const strategyAddress = addresses.PoolController;
    this.strategy = await StrategyContract.at(strategyAddress);
  });

  it("should get want address", async () => {
    const wantAddress = await this.strategy.want();
    console.log(wantAddress);
  });
});
