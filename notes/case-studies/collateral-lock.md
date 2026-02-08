# Case Study: Surplus Collateral Lock in Orderbook Trading

## Vulnerability Type
**Severity**: High  
**Category**: Fund Locking / Logic Error

## Summary

A logic error exists in the `GenericTradePairs.sol` contract where surplus collateral becomes permanently locked when a limit order is filled at a better price than the limit price during continuous trading (non-auction mode). While logic exists to refund surplus collateral in Auction Mode, it's missing from standard matching logic.

## Vulnerability Details

### Problematic Code

In `GenericTradePairs.sol`'s `matchOrder` function, the system matches a Taker order against a Maker order. When a match occurs, `addExecution` is called to settle the trade at the execution price.

For **Auction Mode**, code explicitly handles the case where execution price (Auction Price) is lower than Maker's Limit Price:

```solidity
// Auction Mode Logic
if (tradePair.auctionMode == AuctionMode.MATCHING && makerOrder.price > tradePair.auctionPrice) {
    // Refund difference to available balance
    portfolio.adjustAvailable(
        IPortfolio.Tx.INCREASEAVAIL,
        makerOrder.traderaddress,
        tradePair.quoteSymbol,
        UtilsLibrary.getQuoteAmount(
            tradePair.baseDecimals,
            makerOrder.price - tradePair.auctionPrice,
            quantity
        )
    );
}
```

However, for **Standard Continuous Trading** (using the same `matchOrder` function), this refund logic is completely missing.

### Vulnerability Scenario

1. Maker places limit buy order at price $10, locking 10 units of collateral (Available Balance reduced by 10)
2. This order matches against Taker sell order at execution price $9 (Price Improvement)
3. `portfolio` correctly transfers $9 from Maker to Taker
4. However, the remaining $1 (Surplus) is never unlocked. It remains in Maker's "Total Balance" but is not added back to "Available Balance", making it permanently unusable and non-withdrawable

## Impact

- **Permanent Fund Lock**: Users who receive price improvements (better execution prices) will have the "improved" portion of their funds permanently locked in the protocol
- **Accounting Inconsistency**: From user perspective, `Available Balance + Locked Balance` will no longer equal `Total Balance` (conceptually), as locked amount refers to orders that no longer exist or are fully filled

## Attack Flow

### Reproduction Steps

1. Maker places limit buy order for 100 units @ $10 (Total Lock: $1000)
2. System attempts to match with Taker sell order
3. Simulate scenario where best available price is actually $9 (Price Improvement)
4. Trade executes at $9 (Total Cost: $900)
5. **Expected Result**: Maker should have $100 refunded to Available Balance
6. **Actual Result**: Maker has $0 Available Balance. The $100 surplus is locked

### Proof of Concept Code

```solidity
function testSurplusLock_PassiveMaker_BetterPrice() public {
    uint256 quantity = 100 * 10**18;
    uint256 makerPrice = 10 * 10**18; // Limit Buy @ 10
    uint256 executionPrice = 9 * 10**18; // Executed @ 9 (Better for Buyer)

    // 1. Maker places Limit Buy @ 10
    uint256 depositAmount = 1000 * 10**18;
    deposit(maker, QUOTE_SYMBOL, depositAmount);

    vm.prank(maker);
    ITradePairs.NewOrder memory buyOrder = ITradePairs.NewOrder({
        clientOrderId: bytes32(0),
        tradePairId: PAIR_ID,
        price: makerPrice,
        quantity: quantity,
        traderaddress: maker,
        side: ITradePairs.Side.BUY,
        type1: ITradePairs.Type1.LIMIT,
        type2: ITradePairs.Type2.GTC,
        stp: ITradePairs.STP.NONE
    });
    tradePairs.addNewOrder(buyOrder);

    // Verify Maker Locked Funds
    (uint256 totalBefore, uint256 availBefore, ) = portfolio.getBalance(maker, QUOTE_SYMBOL);
    assertEq(availBefore, 0, "Maker funds should be fully locked");

    // 2. Prepare Taker Sell
    deposit(taker, BASE_SYMBOL, quantity);
    
    // 3. Mock OrderBooks to return lower price (9) simulating price improvement
    vm.mockCall(
        address(orderBooks),
        abi.encodeWithSelector(OrderBooks.getTopOfTheBook.selector, buyBookId),
        abi.encode(executionPrice, topOrderId)
    );

    // 4. Place Taker Order
    vm.prank(taker);
    tradePairs.addNewOrder(sellOrder);

    // 5. Verify Maker Balance
    (uint256 totalAfter, uint256 availAfter, ) = portfolio.getBalance(maker, QUOTE_SYMBOL);
    
    assertEq(totalAfter, 100 * 10**18, "Total remaining should be 100 (1000 - 900)");
    
    // Vulnerability Confirmation
    if (availAfter == 0) {
        console.log("VULNERABILITY CONFIRMED: Surplus 100 is LOCKED.");
    }
    assertEq(availAfter, 0, "VULNERABILITY: Available is 0 (Surplus Locked)");
}
```

## Remediation

Update `matchOrder` function in `GenericTradePairs.sol` to include surplus refund logic for standard continuous trading, similar to existing Auction Mode implementation.

```solidity
// In matchOrder function (standard matching block):

_takerOrder = addExecution(makerOrder.id, _takerOrder, price, quantity);

// --- ADDED FIX ---
if (makerOrder.price > price) {
    portfolio.adjustAvailable(
        IPortfolio.Tx.INCREASEAVAIL,
        makerOrder.traderaddress,
        tradePair.quoteSymbol,
        UtilsLibrary.getQuoteAmount(
            tradePair.baseDecimals,
            makerOrder.price - price,
            quantity
        )
    );
}
// -----------------
```

## Key Takeaways

1. **Price Improvement Handling**: When actual execution price is better than limit price, difference must be properly handled
2. **Mode Consistency**: Different trading modes (auction/continuous) should have consistent fund handling logic
3. **Balance Management**: Locked funds must be correctly released when orders complete or cancel
4. **Test Coverage**: Need to test price improvement scenarios, not just exact matches

## Related Concepts

- Orderbook matching mechanism
- Limit order execution
- Price Improvement
- Collateral management

---

**Tags**: #orderbook #collateral-lock #price-improvement #dex
