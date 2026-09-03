// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseRelayer} from "./BaseRelayer.sol";
import {Types} from "./Types.sol";

contract L2Relayer is BaseRelayer {
    event MessageSent(
        address indexed sender,
        address indexed target,
        bytes message
    );

    constructor(address l1Relayer) BaseRelayer(l1Relayer) {
        require(l1Relayer != address(0), "zero L1 relayer");
    }

    function _sendInitialMessage(
        address target,
        bytes memory message
    ) internal override {
        bytes memory encodedMessage = abi.encode(
            Types.Message({sender: msg.sender, target: target, data: message})
        );

        emit MessageSent(msg.sender, target, encodedMessage);
    }
}
