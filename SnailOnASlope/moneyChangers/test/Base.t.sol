// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {MockEndpoint} from "../src/MockEndpoint.sol";
import {MarketPool} from "../src/MarketPool.sol";
import {LedgerStorage} from "../src/LedgerStorage.sol";
import {HomeRouter} from "../src/HomeRouter.sol";
import {BridgeRouter} from "../src/BridgeRouter.sol";

abstract contract BaseTest is Test {
    uint32 internal constant EID_A = 111;
    uint32 internal constant EID_B = 222;
    uint256 internal constant RATE = uint256(0.05e18) / 365 days; // 5% a year
    uint256 internal constant REWARD_SPEED = 1e18; // 1 TITHE per second per market

    struct Deployment {
        uint32 eid;
        MockERC20 usdc;
        MockERC20 tithe;
        MarketPool market;
        LedgerStorage store;
        HomeRouter core;
        BridgeRouter xr;
    }

    MockEndpoint internal endpoint;
    Deployment internal A;
    Deployment internal B;

    address internal lp = makeAddr("lp");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        endpoint = new MockEndpoint();

        A = _deployChain(EID_A);
        B = _deployChain(EID_B);

        A.store.setDestMarket(address(A.usdc), EID_B, address(B.market));
        B.store.setDestMarket(address(B.usdc), EID_A, address(A.market));

        // liquidity on both chains
        _supply(A, lp, 100_000e18);
        _supply(B, lp, 100_000e18);
    }

    // Overridable deployments

    function _deployStorage(
        uint32 eid
    ) internal virtual returns (LedgerStorage) {
        return new LedgerStorage(eid);
    }

    function _deployCore(
        LedgerStorage store,
        MockERC20 tithe
    ) internal virtual returns (HomeRouter) {
        return new HomeRouter(store, tithe);
    }

    function _deployChain(uint32 eid) internal returns (Deployment memory c) {
        c.eid = eid;
        c.usdc = new MockERC20("USD Coin", "USDC");
        c.tithe = new MockERC20("Tithe", "TITHE");
        c.market = new MarketPool(c.usdc, RATE);
        c.store = _deployStorage(eid);
        c.core = _deployCore(c.store, c.tithe);
        c.xr = new BridgeRouter(c.store, c.core, address(endpoint), eid);

        c.market.setHomeRouter(address(c.core));
        c.market.setBorrowRewardSpeed(REWARD_SPEED);
        c.store.setAuthorized(address(c.core), true);
        c.store.setAuthorized(address(c.xr), true);
        c.store.addMarket(address(c.usdc), address(c.market));
        c.core.setBridgeRouter(address(c.xr));
        endpoint.register(eid, address(c.xr));
    }

    // Helpers

    function _fund(
        Deployment storage c,
        address user,
        uint256 amount
    ) internal {
        c.usdc.mint(user, amount);
        vm.prank(user);
        c.usdc.approve(address(c.core), type(uint256).max);
    }

    function _supply(
        Deployment storage c,
        address user,
        uint256 amount
    ) internal {
        _fund(c, user, amount);
        vm.prank(user);
        c.core.supply(amount, address(c.usdc));
    }

    function _borrowSame(
        Deployment storage c,
        address user,
        uint256 amount
    ) internal {
        vm.prank(user);
        c.core.borrow(amount, address(c.usdc));
    }

    function _borrowCross(address user, uint256 amount) internal {
        vm.prank(user);
        A.xr.startRemoteBorrow(amount, address(A.usdc), EID_B);
        endpoint.deliverAll();
    }

    function _fundRewards(Deployment storage c, uint256 amount) internal {
        c.tithe.mint(address(c.core), amount);
    }

    function _claim(Deployment storage c, address who) internal {
        address[] memory holders = new address[](1);
        holders[0] = who;
        c.core.claimTithe(holders, address(c.market));
    }
}
