// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Types} from "../Protocol/Types.sol";

interface IRouterL1 {
    function executeMessage(Types.Withdrawal calldata withdrawal) external;
}

contract AttackerContract {
    bool public toRevert;
    address public routerAddress;
    bytes dataToSend;

    constructor(address _routerAddress) {
        routerAddress = _routerAddress;
        toRevert = true;
    }

    function setRevert(bool _toRevert) external {
        toRevert = _toRevert;
    }

    function setInputForCall(Types.Withdrawal memory withdrawal) external {
        dataToSend = abi.encodeWithSelector(
            IRouterL1.executeMessage.selector,
            withdrawal
        );
    }

    function attack() external {
        if (toRevert) {
            revert();
        } else {
            (bool success, ) = routerAddress.call(dataToSend);
        }
    }
}
