// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library SimpleSafeCall {
    function call(address target, bytes memory data) internal returns (bool) {
        bool success;

        assembly {
            success := call(
                gas(),
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }

        return success;
    }
}
