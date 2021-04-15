build: contracts/strategy/StrategyBalancerMettalexV3.sol contracts/helper/StrategyHelper.sol
	npx oz compile

deploy:
#	npx oz create -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --init initialize --args 0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7 StrategyBalancerMettalex
	npx oz deploy -n development -k upgradeable -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 StrategyBalancerMettalex 0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7

upgrade:
	npx oz upgrade -n development --init initialize --args 0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7 StrategyBalancerMettalex

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts-ethereum-package@2.5
	npm audit fix
	rm -rf .openzeppelin
	npx oz init pool-controller --no-interactive