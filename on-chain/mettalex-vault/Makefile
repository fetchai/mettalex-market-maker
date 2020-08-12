build: contracts/Vault.sol contracts/PositionTokenV2.sol
	npx oz compile

contracts/Vault.sol:
	cp ../../../mettalex-protocol/contracts/Vault.sol contracts

contracts/PositionTokenV2.sol:
	cp ../../../mettalex-protocol/contracts/PositionTokenV2.sol contracts


init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	npx oz init --no-interactive