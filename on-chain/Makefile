deploy:
	make --directory=mettalex-balancer deploy_pool_factory
	make --directory=mettalex-balancer deploy_balancer_amm
#	make --directory=mettalex-coin deploy
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
	make --directory=mettalex-yearn deposit
	make --directory=mettalex-yearn earn
