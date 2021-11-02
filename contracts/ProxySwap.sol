// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './FocusLP.sol';
import './interfaces/IFocusLP.sol';

contract ProxySwap {
  IERC20 public _tokenA;
  IERC20 public _tokenB;

  // assuming single LP (multiple LPs to be implemented after POC)
  FocusLP private _theLP;

  constructor(address tokenA, address tokenB) {
    _tokenA = IERC20(tokenA);
    _tokenB = IERC20(tokenB);
  }

  function mintLP(uint256 amountA, uint256 amountB, uint256 rangeL, uint256 rangeU) external returns (FocusLP) {
    // todo: revert if price A/B out of range
    _theLP = FocusLP(new FocusLP(_tokenA, _tokenB, amountA, amountB, rangeL, rangeU));
    return _theLP;
  }
}
