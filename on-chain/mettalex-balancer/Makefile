build: contracts/BFactory.sol
	npx oz compile

contracts/BFactory.sol:
	cp ../balancer-core/contracts/B*.sol contracts

init:
	npm init -y
	npm install @openzeppelin/cli
	npm install @openzeppelin/contracts@2.5
	npm audit fix
	npx oz init mettalex-balancer --no-interactive