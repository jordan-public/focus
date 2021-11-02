// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './FocusToken.sol';
import './interfaces/IFocusToken.sol';
import './interfaces/IFocusLP.sol';

contract FocusLP {
  FocusToken public _fTokenA;
  FocusToken public _fTokenB;
  uint256 public _rangeL;
  uint256 public _rangeU;

  constructor(IERC20 tokenA, IERC20 tokenB, uint256 amountA, uint256 amountB, uint256 rangeL, uint256 rangeU) {
    _fTokenA = FocusToken(new FocusToken(tokenA, amountA));
    _fTokenB = FocusToken(new FocusToken(tokenB, amountB));
    _rangeL = rangeL;
    _rangeU = rangeU;
  }
}
