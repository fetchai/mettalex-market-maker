build: contracts/Vault.sol contracts/PositionTokenV2.sol
	npx oz compile


deploy_long:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 PositionToken 'Long Position' LTOK 6 1

deploy_short:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 PositionToken 'Short Position' LTOK 6 1

deploy_vault:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 Vault 'Mettalex Vault' 1 0xCfEB869F69431e42cdB54A4F4f105C19C080A601 0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B 0xC89Ce4735882C9F0f0FE26686c53074E09B0D550 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78 300000000 200000000 100000000 300

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