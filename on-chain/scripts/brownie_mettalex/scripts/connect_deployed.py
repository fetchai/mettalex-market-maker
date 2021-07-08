from brownie import accounts, Contract
import json
import os
from pathlib import Path


def connect_deployed(deployment_file=None):
    deployment_file = deployment_file or 'local_deployment.json'
    file_path = Path(__file__).parent.parent
    with open(os.path.join(file_path, deployment_file), 'r') as f:
        deployed = json.load(f)

    print(deployed.keys())
    contracts = {
        k: Contract.from_abi(k, v['address'], v['abi'])
        for k, v in deployed.items()
    }
    return contracts


def set_oracle(vault, admin, oracle):
    vault.updateOracle(oracle, {'from': admin})


def scenario(contracts, actors):
    admin = actors['admin']
    oracle = actors['oracle']
    maker = actors['maker']
    trader = actors['trader']
    lp = actors['lp']

    coin = contracts['coin']
    vault = contracts['vault']
    pool = contracts['y_vault']
    # to complete


def main(deployment_file=None):
    contracts = connect_deployed(deployment_file)
    if len(accounts) > 0:
        actors = {
            'admin': accounts[0],
            'oracle': accounts[1],
            'maker': accounts[2],
            'trader': accounts[3],
            'lp': accounts[4],
            'provider': accounts[5]
        }
    else:
        actors = None

    return contracts, actors
