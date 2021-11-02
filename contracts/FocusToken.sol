// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import './interfaces/IFocusToken.sol';

contract FocusToken is ERC20, IFocusToken {
  IERC20 public _underlyingToken;
  uint256 public factor;

  constructor(IERC20 underlyingToken, uint256 initialSupply) ERC20("FocusToken", "fTOKEN") {
    _underlyingToken = underlyingToken;
    factor = 1 * 10^18;
    _mint(msg.sender, initialSupply);
  }
}
