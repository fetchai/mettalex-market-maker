cd ../scripts/

npx ganache-cli -p 8545

bash compile.sh

python3 mettalex_contract_setup.py -n local -v 2 -a setup

