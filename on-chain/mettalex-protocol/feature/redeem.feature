Feature: Token Redeeming
    Users Redeem collateral by burning Long and Short position tokens 

    Background: Contracts are ready to use
        Given The Vault contract is deployed with a feerate of 300, cap of "62500000", floor of "37500000" and multiplier "100000000"
        And The the Long and Short Position Tokens are deployed
        And The Vault Contract is whitelisted in both both Position Tokens
        And And USDT is the deployed Collateral Token
        And AMM and the user have approved Vault contract to transfer tokens on their behalf
        And 2 Long and Short token pairs have been minted

    Scenario: Normal user tries to Redeem tokens
        When Normal user tries to Redeem 1 token
        Then Fee of 0 USDT is deducted
        And "2500000000000000" USDT are sent to the caller

    Scenario: AMM tries to Redeem tokens
        When AMM user tries to Redeem 1 token
        Then Fee of 0 USDT is deducted
        And "2500000000000000" USDT are sent to the caller
