build: contracts/yVault.sol contracts/Controller.sol
	npx oz compile

deploy_controller:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 Controller 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1

deploy_vault:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 yVault 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7


contracts/yVault.sol:
	echo 'Copy from https://etherscan.io/address/0x5dbcf33d8c2e976c6b560249878e6f1491bca25c#code'

contracts/Controller.sol:
	echo 'Copy from https://etherscan.io/address/0x31317f9a5e4cc1d231bdf07755c994015a96a37c#code'

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	npx oz init mettalex-yearn --no-interactive