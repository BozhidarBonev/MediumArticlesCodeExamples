// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingProtocol {
    uint256 public constant FEE_BPS = 100; // 1%
    uint256 public constant BASE_BPS = 10_000; // 100%

    mapping(address => uint256) public totalSupplied;
    mapping(address => uint256) public accruedFees;

    event Supplied(address user, address token, uint256 amount, uint256 fee);

    event FeesClaimed(address token, address receiver, uint256 amount);

    // User supplies tokens to the protocol and 1% is added to accrued fee
    function supply(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        totalSupplied[token] += amount;

        uint256 fee = (amount * FEE_BPS) / BASE_BPS;
        accruedFees[token] += fee;

        emit Supplied(msg.sender, token, amount, fee);
    }

    // Called by ActionRouter when sweeping
    function claimFees(
        address token,
        address receiver
    ) external returns (uint256 amount) {
        amount = accruedFees[token];
        accruedFees[token] = 0;

        if (amount > 0) {
            IERC20(token).transfer(receiver, amount);
        }

        emit FeesClaimed(token, receiver, amount);
    }
}
