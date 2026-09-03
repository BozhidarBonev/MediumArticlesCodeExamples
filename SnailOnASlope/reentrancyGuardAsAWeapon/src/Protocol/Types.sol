// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library Types {
    struct Message {
        address sender;
        address target;
        bytes data;
    }

    struct Withdrawal {
        bytes32 id;
        address sender;
        address target;
        bytes data;
    }
}
