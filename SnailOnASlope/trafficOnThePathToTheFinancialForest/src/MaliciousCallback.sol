// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IOrderCallbackReceiver.sol";

contract MaliciousCallback is IOrderCallbackReceiver {
    address public owner;
    bool public griefModeOn;
    uint256 private sink; // dummy storage slot

    event Called(string which, uint256 gasLeftAtEntry, uint256 gasLeftAtExit);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        griefModeOn = true;
    }

    function flipSwitch() external onlyOwner {
        griefModeOn = !griefModeOn;
    }

    function afterOrderExecution(bytes32) external override {
        uint256 g0 = gasleft();
        if (griefModeOn) {
            _burnGas();
        }
        emit Called("After order execution", g0, gasleft());
    }

    function afterOrderCancellation(bytes32) external override {
        uint256 g0 = gasleft();
        if (griefModeOn) {
            _burnGas();
        }
        emit Called("After order cancellation", g0, gasleft());
    }

    // Run out of gas on purpose
    function _burnGas() internal {
        uint256 counter = sink;
        while (gasleft() > 2000) {
            unchecked {
                counter += 1;
            }
            sink = counter;
        }
    }
}
