// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

import './FocusToken.sol';
import './interfaces/IFocusToken.sol';

contract ProxySwap {
  IERC20 public _tokenA;
  IERC20 public _tokenB;
  FocusToken public _fTokenA;
  FocusToken public _fTokenB;

  uint24 public constant poolFee = 3000; // Constant for the prototype. To be made variable in real product.

  ISwapRouter uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // From https://github.com/Uniswap/v3-periphery/blob/main/deploys.md

  constructor(address tokenA, address tokenB) {
    _tokenA = IERC20(tokenA);
    _tokenB = IERC20(tokenB);
    _fTokenA = FocusToken(new FocusToken(_tokenA));
    _fTokenB = FocusToken(new FocusToken(_tokenA));
  }

  function swapExactOutputSingle(uint256 amountOut) external returns (uint256 amountIn) {
    // The caller must _tokenA.approve(<this contract>, comfortable_amount)

    uint256 amountInMaximum = _tokenA.balanceOf(msg.sender); // To be improved - now it takes the entire balance and returns the change later

    // Transfer the specified amount of _tokenA to this contract.
    TransferHelper.safeTransferFrom(address(_tokenA), msg.sender, address(this), amountInMaximum);

    uint256 amountOutFromUnderlying;
    uint256 amountOutFromFToken;

    // Split up the jobs
    if (_fTokenB.balanceOf(address(this)) > 0) { // Proxy pool has any available liquidity
      if (_fTokenB.toUnderlying(_fTokenB.balanceOf(address(this))) >= amountOut) { // Proxy pool has sufficient liquidity
        amountOutFromFToken = amountOut;
        amountOutFromUnderlying = 0;
      } else {
        amountOutFromFToken = _fTokenB.toUnderlying(_fTokenB.balanceOf(address(this)));
        amountOutFromUnderlying = amountOut - amountOutFromFToken;
      }
    } else {
      amountOutFromFToken = 0;
      amountOutFromUnderlying = amountOut;
    }

    amountIn = 0; // so far
    
    if (amountOutFromFToken > 0) { // wrap A to fA execute the fA/fB swap and unwrap the fB to B
      // Approve the router to _fTokenA.
      TransferHelper.safeApprove(address(_fTokenA), address(uniswapRouter), _fTokenA.fromUnderlying(amountInMaximum - amountIn));
      uint256 wrapped = _fTokenA.wrap(_fTokenA.fromUnderlying(amountInMaximum - amountIn));

      // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
      // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
      ISwapRouter.ExactOutputSingleParams memory params =
          ISwapRouter.ExactOutputSingleParams({
              tokenIn: address(_fTokenA),
              tokenOut: address(_fTokenB),
              fee: poolFee,
              recipient: address(this), // fTokenB will arrive to this contract, so we can unwrap it later
              deadline: block.timestamp,
              amountOut: _fTokenB.fromUnderlying(amountOutFromFToken),
              amountInMaximum: wrapped,
              sqrtPriceLimitX96: 0
          });

      // Execute the swap.
      uint256 amountInF = uniswapRouter.exactOutputSingle(params);
      _fTokenA.unwrap(wrapped - amountInF); // unwrap the unused input
      amountIn += _fTokenA.toUnderlying(amountInF);

      _fTokenB.unwrap(amountOutFromFToken); // unwrap the output

      TransferHelper.safeApprove(address(_fTokenA), address(uniswapRouter), 0);
    }

    if (amountOutFromUnderlying > 0) { // Proxy directly to Uniswap V3
      // Approve the router to spend _tokenA.
      TransferHelper.safeApprove(address(_tokenA), address(uniswapRouter), amountInMaximum - amountIn);

      // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
      // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
      ISwapRouter.ExactOutputSingleParams memory params =
          ISwapRouter.ExactOutputSingleParams({
              tokenIn: address(_tokenA),
              tokenOut: address(_tokenB),
              fee: poolFee,
              recipient: msg.sender,
              deadline: block.timestamp,
              amountOut: amountOutFromUnderlying,
              amountInMaximum: amountInMaximum - amountIn,
              sqrtPriceLimitX96: 0
          });

      // Execute the swap.
      amountIn += uniswapRouter.exactOutputSingle(params);

      TransferHelper.safeApprove(address(_tokenA), address(uniswapRouter), 0);
    }

    if (amountIn < amountInMaximum) { // Give the change back  
      TransferHelper.safeTransfer(address(_tokenA), msg.sender, amountInMaximum - amountIn);
    }
  }
}
