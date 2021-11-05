// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.22 <0.9.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import './interfaces/IFocusToken.sol';

contract FocusToken is ERC20, IFocusToken {
  address owner;
  IERC20 public _underlyingToken;
  uint256 public _factor; // Tells how many _underlyingToken is one FocusToken (not iverse because of mul/div rounding)

  constructor(IERC20 underlyingToken) ERC20("FocusToken", string(abi.encodePacked("f",ERC20(address(underlyingToken)).name()))) {
    owner = msg.sender;
    _underlyingToken = underlyingToken;
    _factor = 1 * 10^18; // Initially it's 1
  }

  function setFactor(uint256 factor) public {
    require(msg.sender == owner, "Unauthorized");
    require(0 == totalSupply());
    _factor = factor;
  }

  function toUnderlying(uint256 amount) public view returns (uint256) {
    return SafeMath.mul(amount, _factor);
  }

  function fromUnderlying(uint256 amount) public view returns (uint256) {
    return SafeMath.div(amount, _factor);
  }

  function unwrap(uint256 amount) public returns (uint256 u) {
    _burn(msg.sender, amount);
    u = toUnderlying(amount);
    require(_underlyingToken.transfer(msg.sender, u), "BUG - Missing balance");
  }

  function wrap(uint256 amount) public returns (uint256 u) {
    // msg.sender must approve by calling _underlyingToken.approve(<this contract>, <this contract>.toUnderlying(amount))
    u = toUnderlying(amount);
    require(_underlyingToken.transferFrom(msg.sender, address(this), u), "Insufficient balance");
    _mint(msg.sender, amount);
  }

}
