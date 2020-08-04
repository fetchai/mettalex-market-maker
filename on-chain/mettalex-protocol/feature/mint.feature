Feature: Token Minting
    Users mint Long and Short position tokens by locking collateral and paying fee in USDT

    Background: Contracts are ready to use
        Given The Vault contract is deployed with a feerate of 300, cap of "62500000", floor of "37500000" and multiplier "100000000"
        And The the Long and Short Position Tokens are deployed
        And The Vault Contract is whitelisted in both both Position Tokens
        And And USDT is the deployed Collateral Token
        And AMM and the user have approved Vault contract to transfer tokens on their behalf

    Scenario: Normal user tries to mint tokens
        When Normal user tries to mint 1 token pair
        Then Fee of "15000000000000" USDT is deducted
        And "2500000000000000" USDT are locked as collateral

    Scenario: AMM tries to mint tokens
        When AMM user tries to mint 1 token pair
        Then Fee of 0 USDT is deducted
        And "2500000000000000" USDT are locked as collateral
