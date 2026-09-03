// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseRelayer} from "./BaseRelayer.sol";

contract L1Relayer is BaseRelayer {
    address public router;

    constructor(address _router, address l2Relayer) BaseRelayer(l2Relayer) {
        require(_router != address(0), "zero router");

        router = _router;
    }

    function _sendInitialMessage(address, bytes memory) internal override {
        revert("not implemented");
    }
}
