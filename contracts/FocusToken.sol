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
  uint256 public _factorX96; // Tells how many _underlyingToken is one FocusToken (not iverse because of mul/div rounding)

  constructor(IERC20 underlyingToken) ERC20("FocusToken", string(abi.encodePacked("f",ERC20(address(underlyingToken)).name()))) {
    owner = msg.sender;
    _underlyingToken = underlyingToken;
    _factorX96 = 1 << 96; // Initially it's 1.0
  }

  function setFactorX96(uint256 factorX96) public {
    require(msg.sender == owner, "Unauthorized");
    require(0 == totalSupply());
    _factorX96 = factorX96;
  }

  function toUnderlying(uint256 amount) public view returns (uint256) {
    return SafeMath.mul(amount, _factorX96) >> 96;
  }

  function fromUnderlying(uint256 amount) public view returns (uint256) {
    return SafeMath.div(amount << 96, _factorX96);
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
