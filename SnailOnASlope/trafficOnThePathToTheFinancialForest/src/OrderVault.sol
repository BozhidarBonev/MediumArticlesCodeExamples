// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./MockERC20.sol";

contract OrderVault {
    MockERC20 public immutable token;
    address public controller;

    modifier onlyController() {
        require(msg.sender == controller, "OrderVault: not controller");
        _;
    }

    constructor(MockERC20 _token) {
        token = _token;
        controller = msg.sender;
    }

    function setController(address _controller) external {
        require(
            controller == address(0) || msg.sender == controller,
            "Already set"
        );
        controller = _controller;
    }

    function transferOut(address to, uint256 amount) external onlyController {
        require(token.transfer(to, amount), "Transfer failed");
    }
}
