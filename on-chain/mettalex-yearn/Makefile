build: contracts/yVault.sol contracts/Controller.sol
	npx oz compile

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