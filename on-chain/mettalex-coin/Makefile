build: contracts/TetherToken.sol
	npx oz compile

deploy:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 TetherToken 100000000000 'Tether USD' USDT 6

contracts/TetherToken.sol:
	echo 'Copy from https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code'

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	npx oz init mettalex-coin --no-interactive