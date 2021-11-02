Here's what our team is working on so far:

**Name**: Focus
**Description**: A proxy exchange and set of wrapper tokens to improve liquidity efficiency of Uniswap V3.
**Github**: https://github.com/jordan-public/focus
**Idea**: I am going to build a proxy exchange "Focus" which will forward the trades to Uniswap V3, but it will improve the efficiency of the liquidity as well as the profit for the liquidity providers.
While the liquidity on Uniswap V3 may fall out of scope (the current price out of the LP range), Focus liquidity is always in scope. It achieves that by shifting the range of the LP as soon as it falls out of scope. To achieve this, for each token pair traded, it creates a pair of wrapping tokens, which hold the original assets. The wrapping tokens are traded on Uniswap V3, while their prices are manipulated so that the LP traded on Uniswap V3 is always in scope. Focus proxies the trade and provides 2-way mapping for the price conversion of the wrapped tokens.

Public URL: https://showcase.ethglobal.co/unicode/focus
