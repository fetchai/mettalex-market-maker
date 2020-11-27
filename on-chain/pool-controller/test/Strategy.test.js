const { expect } = require("chai");
const { accounts, contract } = require("@openzeppelin/test-environment");
const {
  BN,
  expectEvent,
  expectRevert,
  constants
} = require("@openzeppelin/test-helpers");

const StrategyContract = contract.fromArtifact("StrategyBalancerMettalexV2");

const [governance] = accounts;
const nullAddress = constants.ZERO_ADDRESS;

describe("Strategy", () => {
  beforeEach(async () => {});
});
