import pytest
import brownie

@pytest.fixture(scope="module")
def setup(pm, FeeDistributor, accounts):
    erc20Token = pm('OpenZeppelin/openzeppelin-contracts@3.0.0').ERC20Mock
    token = accounts[0].deploy(erc20Token, "Tether", "USDT", accounts[9], 50*10**18)

    userAddresses = [accounts[1], accounts[2]]
    fractions = [60, 40]
    
    distributor = accounts[0].deploy(
        FeeDistributor, token, accounts[9], userAddresses, fractions)

    yield (distributor, token)

@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass

def test_deploy(setup, accounts):
    fee_distributor = setup[0]
    token = setup[1]

    assert token.name() == "Tether"
    assert token.symbol() == "USDT"
    assert token.balanceOf(accounts[9]) == 50*10**18
    assert fee_distributor.want() == token
    assert fee_distributor.strategy() == accounts[9]
    assert fee_distributor.distributionIndex() == 0
    assert fee_distributor.getTotalFees(0) == 0
    assert fee_distributor.getUserFraction(0, accounts[1]) == 60
    assert fee_distributor.getUserAddresses(0) == [accounts[1], accounts[2]]
    assert fee_distributor.getTotalFees(0) == 0

def test_send_fee(setup, accounts):
    fee_distributor = setup[0]
    token = setup[1]

    token.approve(fee_distributor, 100, {'from': accounts[9]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert token.balanceOf(fee_distributor) == 100
    assert fee_distributor.getBalance(accounts[1]) == 60
    assert fee_distributor.getBalance(accounts[2]) == 40
    assert fee_distributor.getTotalFees(0) == 100

def test_withdraw(setup, accounts):
    fee_distributor = setup[0]
    token = setup[1]

    token.approve(fee_distributor, 100, {'from': accounts[9]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    fee_distributor.withdraw({'from': accounts[1]})
    fee_distributor.withdraw({'from': accounts[2]})

    assert token.balanceOf(accounts[1]) == 60
    assert token.balanceOf(accounts[2]) == 40
    assert fee_distributor.getTotalFees(0) == 100

def test_fraction_update(setup, accounts):
    fee_distributor = setup[0]
    token = setup[1]

    token.approve(fee_distributor, 300, {'from': accounts[9]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert fee_distributor.getBalance(accounts[1]) == 60
    assert fee_distributor.getBalance(accounts[2]) == 40

    fee_distributor.updateFractions([accounts[1], accounts[2], accounts[3]], [60, 20, 20], {'from': accounts[0]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert fee_distributor.distributionIndex() == 1
    assert fee_distributor.getUserAddresses(1) == [accounts[1], accounts[2], accounts[3]]
    assert fee_distributor.getTotalFees(0) == 100
    assert fee_distributor.getTotalFees(1) == 100
    assert fee_distributor.getBalance(accounts[1]) == 120
    assert fee_distributor.getBalance(accounts[2]) == 60
    assert fee_distributor.getBalance(accounts[3]) == 20

    fee_distributor.withdraw({'from': accounts[1]})
    fee_distributor.withdraw({'from': accounts[2]})
    fee_distributor.withdraw({'from': accounts[3]})
    assert token.balanceOf(accounts[1]) == 120
    assert token.balanceOf(accounts[2]) == 60
    assert token.balanceOf(accounts[3]) == 20

def test_withdraw_before_fraction_update(setup, accounts):
    fee_distributor = setup[0]
    token = setup[1]

    token.approve(fee_distributor, 300, {'from': accounts[9]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert fee_distributor.getBalance(accounts[1]) == 60
    assert fee_distributor.getBalance(accounts[2]) == 40

    fee_distributor.withdraw({'from': accounts[1]})
    assert fee_distributor.getBalance(accounts[1]) == 0
    assert token.balanceOf(accounts[1]) == 60

    fee_distributor.updateFractions([accounts[1], accounts[2], accounts[3]], [60, 20, 20], {'from': accounts[0]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert fee_distributor.getTotalFees(0) == 100
    assert fee_distributor.getTotalFees(1) == 100
    assert fee_distributor.getBalance(accounts[1]) == 60
    assert fee_distributor.getBalance(accounts[2]) == 60
    assert fee_distributor.getBalance(accounts[3]) == 20

    fee_distributor.withdraw({'from': accounts[1]})
    fee_distributor.withdraw({'from': accounts[2]})
    fee_distributor.withdraw({'from': accounts[3]})

    assert token.balanceOf(accounts[1]) == 120
    assert token.balanceOf(accounts[2]) == 60
    assert token.balanceOf(accounts[3]) == 20

    fee_distributor.updateFractions([accounts[3], accounts[4]], [50, 50], {'from': accounts[0]})

    fee_distributor.sendFees(100, {'from': accounts[9]})

    assert fee_distributor.distributionIndex() == 2
    assert fee_distributor.getBalance(accounts[1]) == 0
    assert fee_distributor.getBalance(accounts[2]) == 0
    assert fee_distributor.getBalance(accounts[3]) == 50
    assert fee_distributor.getBalance(accounts[4]) == 50

    fee_distributor.withdraw({'from': accounts[1]})
    fee_distributor.withdraw({'from': accounts[2]})
    fee_distributor.withdraw({'from': accounts[3]})
    fee_distributor.withdraw({'from': accounts[4]})

    assert token.balanceOf(accounts[1]) == 120
    assert token.balanceOf(accounts[2]) == 60
    assert token.balanceOf(accounts[3]) == 70
    assert token.balanceOf(accounts[4]) == 50