# Autonomous Market Maker
On-chain market maker to allow traders to enter/exit a single-sided position without going through
the "mint pair and sell one side" flow.

The market maker itself is a private [Balancer](https://github.com/balancer-labs/balancer-core.git) pool
that is rebalanced to set position token prices in line with the underlying asset price.

A separate Pool Controller contract is used for supplying tokens to the Balancer pool (WIP).
