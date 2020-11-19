# Multipool Strategy Controller System (Future Scope)

The hierarchical pool controller strategy is used to manage liquidity in multiple balancer pools which will be used as market maker for different commodities.

The liquidity providers will deposit the tokens to a vault and these tokens will be handled by strategy, which is going to decide where to add the liquidity provided by user.

## Implementation Details

### **Strategy Manager contract**

It manages sub-strategies for each commodity which follows same structure as Stratgey API by yEarn.

**Strategy Management**
* Stores Address array for all commodities. 
* Maps commodities with integers
* Strategy addresses can be added, updated and deleted for each commodity

**Liquidity flow management**

* Through off-chain calculations, keeping in mind the liquidity available in all the pools, addresses for `depositTo` and `withdrawFrom` will be updated.
* For the deposit, whenever the earn() method will be executed, it will transfer the whole liquidity to strategy address stored in `depositTo` address.
* For the withdraw, if the vault does not have enough `want` to withdraw from, Strategy Manager will withdraw the liquidity from commodity pool associated with address of strategy stored in `withdrawFrom` address.
* The total liquidity provided will be the sum of total amount of Coin and position tokens taken in terms of USDT. It will calculated with the help of `balanceOf` method available in all the sub-strategies.

### **Off Chain Calculations for liquidity management**

*  //TODO
