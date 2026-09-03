// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SimpleSafeCall} from "./SimpleSafeCall.sol";
import {Types} from "./Types.sol";

abstract contract BaseRelayer is ReentrancyGuard {
    address public concreteRelayerContract;

    mapping(bytes32 => bool) public processedMessages;
    mapping(bytes32 => bool) public failedMessages;

    event Failed(bytes32 indexed messageHash);
    event RelayedFinal(bytes32 indexed messageHash);

    constructor(address _concreteRelayerContract) {
        concreteRelayerContract = _concreteRelayerContract;
    }

    function setConcreteRelayerContract(address _relayer) external {
        require(concreteRelayerContract == address(0), "already initialized");
        require(_relayer != address(0), "zero address");

        concreteRelayerContract = _relayer;
    }

    function sendInitialMessage(address target, bytes memory message) external {
        _sendInitialMessage(
            concreteRelayerContract,
            abi.encodeWithSelector(
                this.relayFinalMessage.selector,
                msg.sender,
                target,
                message
            )
        );
    }

    function _sendInitialMessage(
        address target,
        bytes memory message
    ) internal virtual;

    function relayFinalMessage(
        address sender,
        address target,
        bytes memory message
    ) external nonReentrant {
        bytes32 messageHash = keccak256(
            abi.encode(
                Types.Message({sender: sender, target: target, data: message})
            )
        );

        /*
         * Normal relay:
         *
         *      msg.sender == paired relayer
         *
         * Retry:
         *
         *      msg.sender != paired relayer
         *      but message must previously have failed.
         */
        if (msg.sender != concreteRelayerContract) {
            require(
                failedMessages[messageHash],
                "message was not previously failed"
            );

            require(
                !processedMessages[messageHash],
                "message already processed"
            );
        } else {
            require(!failedMessages[messageHash], "message already failed");
        }

        bool success = SimpleSafeCall.call(target, message);

        if (!success) {
            failedMessages[messageHash] = true;
            emit Failed(messageHash);
        } else {
            processedMessages[messageHash] = true;
            emit RelayedFinal(messageHash);
        }
    }
}
