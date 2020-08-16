build: contracts/BFactory.sol
	npx oz compile --optimizer on

clean:
	rm -rf build

deploy_pool_factory:
	npx oz deploy -k regular -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 BFactory

deploy_balancer_amm:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab --method newBPool

set_controller_amm:
	npx oz send-tx -n development -f 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1 --to 0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78 --method setController --args 0x9b1f7f645351af3631a656421ed2e40f2802e6c0

contracts/BFactory.sol:
	cp ../balancer-core/contracts/B*.sol contracts

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	rm -rf .openzeppelin
	npx oz init mettalex-balancer --no-interactive