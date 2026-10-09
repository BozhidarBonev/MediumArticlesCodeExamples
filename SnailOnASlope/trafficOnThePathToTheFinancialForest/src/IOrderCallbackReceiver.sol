// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IOrderCallbackReceiver {
    function afterOrderExecution(bytes32 key) external;
    function afterOrderCancellation(bytes32 key) external;
}
