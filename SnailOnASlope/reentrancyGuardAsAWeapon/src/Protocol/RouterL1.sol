// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SimpleSafeCall} from "./SimpleSafeCall.sol";
import {Types} from "./Types.sol";

interface IL1Relayer {
    function relayFinalMessage(
        address sender,
        address target,
        bytes calldata data
    ) external;
}

contract RouterL1 {
    event Executed(bytes32 indexed withdrawalId, bool success);

    mapping(bytes32 => bool) public finalized;

    address public immutable l1Relayer;

    constructor(address _l1Relayer) {
        require(_l1Relayer != address(0), "zero relayer");

        l1Relayer = _l1Relayer;
    }

    function executeMessage(Types.Withdrawal memory withdrawal) external {
        require(!finalized[withdrawal.id], "withdrawal already finalized");

        /*
         * IMPORTANT:
         *
         * We mark the withdrawal finalized BEFORE
         * calling the messenger.
         */
        finalized[withdrawal.id] = true;

        /*
         * This models:
         *
         * OptimismPortal
         *      |
         *      +--> L1CrossDomainMessenger.relayMessage(...)
         *
         * We intentionally ignore the return value.
         */
        bool success = SimpleSafeCall.call(
            l1Relayer,
            abi.encodeWithSelector(
                IL1Relayer.relayFinalMessage.selector,
                withdrawal.sender,
                withdrawal.target,
                withdrawal.data
            )
        );

        /*
         * Vulnerability:
         *
         * Even if success == false, the withdrawal remains
         * finalized.
         */
        emit Executed(withdrawal.id, success);
    }
}
