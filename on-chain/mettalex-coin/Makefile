build: contracts/TetherToken.sol
	npx oz compile

deploy:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 TetherToken 1560000000000000000000000000 'Tether USD' USDT 18

approve_pool_vault:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 --method approve --args 0xe982E462b094850F12AF94d21D470e21bE9D0E9C,1560000000000000000000000000

approve_mettalex_vault:
	# For testing mint operation with mettalex-vault directly
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 --method approve --args 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb,1560000000000000000000000000

contracts/TetherToken.sol:
	echo 'Copy from https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code'

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	rm -rf .openzeppelin
	npx oz init mettalex-coin --no-interactive