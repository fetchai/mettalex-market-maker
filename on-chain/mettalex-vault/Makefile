build: contracts
	npx oz compile

# Coin token in this project - should be able to use mettalex-coin but running into integration issues
deploy_coin:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 CoinToken 'Tether USD' USDT 18

approve_pool_vault:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 --method approve --args 0xe982E462b094850F12AF94d21D470e21bE9D0E9C,1560000000000000000000000000

approve_mettalex_vault:
	# For testing mint operation with mettalex-vault directly
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 --method approve --args 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb,1560000000000000000000000000

# Position tokens
deploy_long:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 PositionToken 'Long Position' LTOK 6 1

deploy_short:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 PositionToken 'Short Position' LTOK 6 1

deploy_vault:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 Vault 'Mettalex Vault' 1 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B 0xC89Ce4735882C9F0f0FE26686c53074E09B0D550 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78 3000000 2000000 100000000 300

whitelist_vault:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B --method setWhitelist --args 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb,true
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xC89Ce4735882C9F0f0FE26686c53074E09B0D550 --method setWhitelist --args 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb,true

test_mint:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xD833215cBcc3f914bD1C9ece3EE7BF8B14f841bb --method mintPositions --args 100000000

balanceOf_pool_controller:
	npx oz call -n development --to 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 --method balanceOf --args 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0
	npx oz call -n development --to 0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B --method balanceOf --args 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0
	npx oz call -n development --to 0xC89Ce4735882C9F0f0FE26686c53074E09B0D550 --method balanceOf --args 0x9b1f7F645351AF3631a656421eD2e40f2802E6c0

contracts:
	cp -R ../../../mettalex-protocol/contracts/ contracts


init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.3
	npm audit fix
	rm -rf .openzeppelin
	npx oz init mettalex-vault --no-interactive