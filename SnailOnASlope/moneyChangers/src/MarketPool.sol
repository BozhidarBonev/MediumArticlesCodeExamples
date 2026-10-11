// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {MockERC20} from "./MockERC20.sol";

contract MarketPool {
    MockERC20 public immutable underlying;
    uint256 public immutable ratePerSecond; // 1e18
    uint256 public immutable startTime;

    address public owner;
    address public homeRouter;

    // total borrowed amount
    uint256 public totalPrincipal;

    // TITHE emissions to borrowers
    uint256 public borrowRewardSpeed; // TITHE wei per second
    uint256 public borrowRewardIndex = 1e36;
    uint256 public rewardTimestamp;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyCore() {
        require(msg.sender == homeRouter, "Not core router");
        _;
    }

    constructor(MockERC20 _underlying, uint256 _ratePerSecond) {
        underlying = _underlying;
        ratePerSecond = _ratePerSecond;
        startTime = block.timestamp;
        rewardTimestamp = block.timestamp;
        owner = msg.sender;
    }

    function setHomeRouter(address _homeRouter) external onlyOwner {
        homeRouter = _homeRouter;
    }

    // View funcs

    function setBorrowRewardSpeed(uint256 speed) external onlyOwner {
        updateBorrowRewardIndex();
        borrowRewardSpeed = speed;
    }

    function borrowIndex() public view returns (uint256) {
        return 1e18 + ratePerSecond * (block.timestamp - startTime);
    }

    function totalBorrows() public view returns (uint256) {
        return (totalPrincipal * borrowIndex()) / 1e18;
    }

    function getCash() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    // External funcs

    function release(uint256 amount) external onlyCore {
        require(getCash() >= amount, "Insufficient cash");
        updateBorrowRewardIndex();
        totalPrincipal += (amount * 1e18) / borrowIndex();
        underlying.transfer(msg.sender, amount);
    }

    function onRepay(uint256 amount) external onlyCore {
        updateBorrowRewardIndex();
        uint256 principal = (amount * 1e18) / borrowIndex();
        totalPrincipal = principal > totalPrincipal
            ? 0
            : totalPrincipal - principal;
    }

    function updateBorrowRewardIndex() public {
        uint256 dt = block.timestamp - rewardTimestamp;
        if (dt == 0) return;
        rewardTimestamp = block.timestamp;
        if (totalPrincipal == 0 || borrowRewardSpeed == 0) return;
        borrowRewardIndex += (dt * borrowRewardSpeed * 1e36) / totalPrincipal;
    }
}
