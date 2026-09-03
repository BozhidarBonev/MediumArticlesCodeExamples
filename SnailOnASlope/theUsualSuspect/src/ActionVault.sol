// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IActionRouter {
    function sweepFees(address[] calldata tokens) external;
}

contract ActionVault is ReentrancyGuard {
    IERC20 public immutable lpt;
    IActionRouter public immutable actionRouter;

    address public feeOperator;

    constructor(address _lpt, address _actionRouter, address _feeOperator) {
        lpt = IERC20(_lpt);
        actionRouter = IActionRouter(_actionRouter);
        feeOperator = _feeOperator;
    }

    modifier onlyFeeOperator() {
        require(msg.sender == feeOperator, "Fee operator required");
        _;
    }

    // Sweep fees and send LPT to the fee operator
    function sweepFeesAndTransfer(
        address[] calldata tokens
    ) external onlyFeeOperator nonReentrant returns (uint256) {
        uint256 beforeBalance = lpt.balanceOf(address(this));

        actionRouter.sweepFees(tokens);

        uint256 afterBalance = lpt.balanceOf(address(this));

        uint256 net = afterBalance - beforeBalance;

        if (net > 0) {
            require(lpt.transfer(msg.sender, net), "LPT transfer failed");
        }

        return net;
    }
}
