// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

import './FocusToken.sol';
import './interfaces/IFocusToken.sol';

contract ProxySwap {
  uint256 public constant MAX_INT = 2**256 - 1;

  // From https://github.com/Uniswap/v3-periphery/blob/main/deploys.md
  ISwapRouter public constant uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); 
  IQuoter public constant uniswapQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
  INonfungiblePositionManager public constant nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

  uint24 public constant poolFee = 3000; // Constant for the prototype. To be made variable in real product.

  struct Asset {
    IERC20 token;
    FocusToken fToken;
    uint256 myLPRangeLower96;
  }

  Asset public A;
  Asset public B;

  address owner;

  constructor(address tokenA, address tokenB) {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA); // To be comaptible with Uniswap
    owner = msg.sender;
    A.token = IERC20(tokenA);
    B.token = IERC20(tokenB);
    A.fToken = FocusToken(new FocusToken(A.token));
    B.fToken = FocusToken(new FocusToken(B.token));
    // Approvals stay forever
    TransferHelper.safeApprove(address(A.token), address(uniswapRouter), MAX_INT); // Uniswap can move ProxySwap's A.token
    TransferHelper.safeApprove(address(B.token), address(uniswapRouter), MAX_INT); // Uniswap can move ProxySwap's B.token
    TransferHelper.safeApprove(address(A.fToken), address(uniswapRouter), MAX_INT); // Uniswap can move ProxySwap's A.fToken
    TransferHelper.safeApprove(address(B.fToken), address(uniswapRouter), MAX_INT); // Uniswap can move ProxySwap's B.fToken
    require(A.token.approve(address(A.fToken), MAX_INT)); // A.fToken can wrap ProxySwap's A.token
    require(B.token.approve(address(B.fToken), MAX_INT)); // B.fToken can wrap ProxySwap's B.token
  }

  function toRatioX96(int24 tick) private pure returns (uint256 ratioX96) {
    ratioX96 = TickMath.getSqrtRatioAtTick(tick);
    ratioX96 *= ratioX96;
    ratioX96 >>= 96;
  }

  // @dev As for this POC we use single LP NFT, connect the LP NFT to this contract.
  function setMyLP(uint256 tokenID) external {
    require(msg.sender == owner);
    ( , , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenID);
    require(token0 == address(A.token) && token1 == address(B.token), "Wrong tokens");
    require(poolFee == fee, "Wrong pool (fee)");
    (A.myLPRangeLower96, B.myLPRangeLower96) = (toRatioX96(tickLower), toRatioX96(tickUpper));
  }

  function swapExactOutput(uint256 amountOut) external returns (uint256 amountIn) {
    amountIn = swapExactOutput(A, B, amountOut);
  }

  function swapExactOutputReverse(uint256 amountOut) external returns (uint256 amountIn) {
    amountIn = swapExactOutput(B, A, amountOut);
  }

  function swapExactOutput(Asset storage from, Asset storage to, uint256 amountOut) internal returns (uint256 amountIn) {
    // The caller must from.token.approve(<this contract>, comfortable_amount)

    uint256 amountInMaximum = from.token.balanceOf(msg.sender); // To be improved - now it takes the entire balance and returns the change later

    // Transfer the specified amount of from.token to this contract.
    TransferHelper.safeTransferFrom(address(from.token), msg.sender, address(this), amountInMaximum);

    uint256 amountOutFromUnderlying;
    uint256 amountOutFromFToken;

    // Split up the jobs
    if (to.fToken.balanceOf(address(this)) > 0) { // Proxy pool has any available liquidity
      if (to.fToken.toUnderlying(to.fToken.balanceOf(address(this))) >= amountOut) { // Proxy pool has sufficient liquidity
        amountOutFromFToken = amountOut;
        amountOutFromUnderlying = 0;
      } else {
        amountOutFromFToken = to.fToken.toUnderlying(to.fToken.balanceOf(address(this)));
        amountOutFromUnderlying = amountOut - amountOutFromFToken;
      }
    } else {
      amountOutFromFToken = 0;
      amountOutFromUnderlying = amountOut;
    }

    amountIn = 0; // so far
    
    if (amountOutFromFToken > 0) { // wrap A to fA execute the fA/fB swap and unwrap the fB to B

      // But, before we exchange let's check if there is an opportunity to re-price (re-focus) the fTokenA
      if (0 == from.fToken.balanceOf(address(this))) { // No fTokenA liquidity - we can from.fToken.setFactor to adjust and bring lowerBound of from.token equal to the spot price
                                                    // This will bring our f-liquidity at the edge of the current price - the best that we can do 
        // Check the current Uniswap spot price: how many to.token can we get for 1 from.token?
        uint256 tokenToFor1TokenFrom = uniswapQuoter.quoteExactInputSingle(address(from.token), address(to.token), poolFee, 1 << ERC20(address(from.token)).decimals(), 0); // To improve: not exact + gas consuming

        // Re-focus: change the factor so the current Uniswap spot parice matches the low end of the fTokenA liquidity range 
        from.fToken.setFactorX96((tokenToFor1TokenFrom << 96 / from.myLPRangeLower96) << LowGasSafeMath.sub(uint256(96), uint256(ERC20(address(to.token)).decimals())));
      }

      // No need - see constructor: TransferHelper.safeApprove(address(from.fToken), address(uniswapRouter), from.fToken.fromUnderlying(amountInMaximum - amountIn));

      uint256 wrapped = from.fToken.wrap(from.fToken.fromUnderlying(amountInMaximum - amountIn));

      // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
      // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
      ISwapRouter.ExactOutputSingleParams memory params =
          ISwapRouter.ExactOutputSingleParams({
              tokenIn: address(from.fToken),
              tokenOut: address(to.fToken),
              fee: poolFee,
              recipient: address(this), // fTokenB will arrive to this contract, so we can unwrap it later
              deadline: block.timestamp,
              amountOut: to.fToken.fromUnderlying(amountOutFromFToken),
              amountInMaximum: wrapped,
              sqrtPriceLimitX96: 0
          });

      // Execute the swap.
      uint256 amountInF = uniswapRouter.exactOutputSingle(params);
      from.fToken.unwrap(wrapped - amountInF); // unwrap the unused input - will send change at the end
      amountIn += from.fToken.toUnderlying(amountInF);

      TransferHelper.safeTransfer(address(to.token), msg.sender, to.fToken.unwrap(amountOutFromFToken)); // unwrap and send the output

      // No need - see constructor: TransferHelper.safeApprove(address(from.fToken), address(uniswapRouter), 0);
    }

    if (amountOutFromUnderlying > 0) { // Proxy directly to Uniswap V3
      // No need - see constructor: TransferHelper.safeApprove(address(from.token), address(uniswapRouter), amountInMaximum - amountIn);

      // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
      // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
      ISwapRouter.ExactOutputSingleParams memory params =
          ISwapRouter.ExactOutputSingleParams({
              tokenIn: address(from.token),
              tokenOut: address(to.token),
              fee: poolFee,
              recipient: msg.sender,
              deadline: block.timestamp,
              amountOut: amountOutFromUnderlying,
              amountInMaximum: amountInMaximum - amountIn,
              sqrtPriceLimitX96: 0
          });

      // Execute the swap.
      amountIn += uniswapRouter.exactOutputSingle(params);

      // No need - see constructor: TransferHelper.safeApprove(address(from.token), address(uniswapRouter), 0);
    }

    if (amountIn < amountInMaximum) { // Send back the change
      TransferHelper.safeTransfer(address(from.token), msg.sender, amountInMaximum - amountIn);
    }
  }
}
