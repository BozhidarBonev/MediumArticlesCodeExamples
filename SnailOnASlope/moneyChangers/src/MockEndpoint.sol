// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

interface IEndpoint {
    function send(uint32 dstEid, bytes calldata payload) external;
}

interface IReceiver {
    function receiveMessage(uint32 srcEid, bytes calldata payload) external;
}

contract MockEndpoint is IEndpoint {
    struct Message {
        uint32 srcEid;
        uint32 dstEid;
        bytes payload;
    }

    Message[] public queue;
    uint256 public nextIndex;

    mapping(uint32 => address) public routerOf;
    mapping(address => uint32) public eidOf;

    function register(uint32 eid, address router) external {
        routerOf[eid] = router;
        eidOf[router] = eid;
    }

    function send(uint32 dstEid, bytes calldata payload) external {
        uint32 srcEid = eidOf[msg.sender];
        require(srcEid != 0, "Unregistered sender");
        require(routerOf[dstEid] != address(0), "Unknown destination");
        queue.push(Message(srcEid, dstEid, payload));
    }

    function pending() external view returns (uint256) {
        return queue.length - nextIndex;
    }

    function deliverAll() external {
        while (nextIndex < queue.length) {
            Message memory m = queue[nextIndex++];
            IReceiver(routerOf[m.dstEid]).receiveMessage(m.srcEid, m.payload);
        }
    }
}
