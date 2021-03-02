import brownie
from brownie import accounts, FeeDistributor

def main():
    token = accounts[9]
    strategy = accounts[8]
    userAddresses = [accounts[1], accounts[2]]
    fractions = [60, 40]
    
    accounts[0].deploy(
        FeeDistributor, token, strategy, userAddresses, fractions)