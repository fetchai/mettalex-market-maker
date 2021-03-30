init:
	cd mettalex-balancer/ && npm install &&	npx oz compile
	cd mettalex-coin/ && npm install &&	npx oz compile
	cd mettalex-bridge/ && npm install && npx oz compile
	cd mettalex-faucet/ && npm install &&	npx oz compile
	cd mettalex-vault/ &&	npm install &&	npx oz compile
	cd mettalex-yearn/ &&	npm install &&	npx oz compile
	cd pool-controller/ && npm install &&	npx oz compile
	cd scripts/ && pip3 install -r requirements.txt


deploy:
	make --directory=mettalex-balancer deploy_pool_factory
	make --directory=mettalex-balancer deploy_balancer_amm
	make --directory=mettalex-coin build  # NB: Pool controller fails if actual USDT contract is used
	make --directory=mettalex-vault deploy_coin
	make --directory=mettalex-vault deploy_long
	make --directory=mettalex-vault deploy_short
	make --directory=mettalex-vault deploy_vault
	make --directory=mettalex-yearn deploy_controller
	make --directory=mettalex-yearn deploy_vault
	make --directory=pool-controller deploy
	make --directory=mettalex-vault whitelist_vault
	make --directory=mettalex-yearn set_strategy
#	make --directory=mettalex-coin approve_pool_vault
	make --directory=mettalex-vault approve_pool_vault

earn:
	# python3 setup_contracts.py  # TODO: Need to call this in correct pipenv
	make --directory=mettalex-yearn deposit
	make --directory=mettalex-yearn earn
	make --directory=mettalex-vault balanceOf_pool_controller