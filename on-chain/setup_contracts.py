import os
from pathlib import Path
import json

os.environ['WEB3_PROVIDER_URI'] = 'http://127.0.0.1:8545'


def connect():
    from web3.auto import w3
    from web3.middleware import construct_sign_and_send_raw_middleware

    admin = w3.eth.account.from_key('0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d')
    w3.middleware_onion.add(construct_sign_and_send_raw_middleware(admin))
    w3.eth.defaultAccount = admin.address
    return w3, admin


def connect_balancer(w3):
    build_file = Path(__file__).parent / 'mettalex-balancer' / 'build' / 'contracts' / 'BPool.json'
    with open(build_file, 'r') as f:
        contract_details = json.load(f)

    # get abi
    abi = contract_details['abi']
    balancer = w3.eth.contract(abi=abi, address='0xcC5f0a600fD9dC5Dd8964581607E5CC0d22C5A78')
    return balancer


if __name__ == '__main__':
    w3, admin = connect()
    balancer = connect_balancer(w3)
    controller_address = '0x9b1f7F645351AF3631a656421eD2e40f2802E6c0'
    tx_hash = balancer.functions.setController(controller_address).transact({'from': admin.address, 'gas': 1_000_000})
    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    balancer_controller = balancer.functions.getController().call()
    print(f'Balancer controller {balancer_controller}')
