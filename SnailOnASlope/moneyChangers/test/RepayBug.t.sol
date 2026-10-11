// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {BaseTest} from "./Base.t.sol";
import {LedgerStorage} from "../src/LedgerStorage.sol";

contract RepayBugTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _supply(A, alice, 10_000e18); // Alice's collateral on chain A
    }

    function test_crossChainBorrowLandsOnBothChains() public {
        _borrowCross(alice, 5_000e18);

        assertEq(B.usdc.balanceOf(alice), 5_000e18);

        LedgerStorage.Loan[] memory onB = B.store.getForeignBackedLoans(
            alice,
            address(B.usdc)
        );
        assertEq(onB.length, 1);
        assertEq(onB[0].srcEid, EID_A);
        assertEq(onB[0].destEid, EID_B);
        assertEq(onB[0].principal, 5_000e18);

        LedgerStorage.Loan[] memory onA = A.store.getOutboundLoans(
            alice,
            address(A.usdc)
        );
        assertEq(onA.length, 1);
        assertEq(onA[0].srcEid, EID_A);
        assertEq(onA[0].destEid, EID_B);

        (uint256 borrowed, uint256 collateral) = A.store.accountPosition(
            alice,
            address(A.market),
            0
        );
        assertEq(borrowed, 5_000e18);
        assertEq(collateral, 7_500e18);
    }

    // Control group
    function test_controlSameChainRepayWorks() public {
        _supply(B, carol, 10_000e18);
        _borrowSame(B, carol, 5_000e18);
        skip(30 days);

        uint256 debt = B.store.sameChainDebt(carol, address(B.market));
        assertGt(debt, 5_000e18);

        B.usdc.mint(carol, debt);
        vm.prank(carol);
        B.core.repayBorrow(type(uint256).max, address(B.market));

        assertEq(B.store.sameChainDebt(carol, address(B.market)), 0);
        assertLe(B.market.totalPrincipal(), 2);
    }

    // Alice cannot repay, whatever she tries.
    function test_crossChainRepayAlwaysReverts() public {
        _borrowCross(alice, 5_000e18);
        skip(30 days);

        (uint256 owed, , ) = B.xr.remoteBorrowDetails(
            alice,
            address(B.usdc),
            address(B.market),
            EID_A
        );
        assertGt(owed, 5_000e18);

        assertEq(B.store.crossChainDebt(alice, address(B.market)), 0);

        B.usdc.mint(alice, owed);
        vm.startPrank(alice);
        B.usdc.approve(address(B.core), type(uint256).max);

        vm.expectRevert("Borrowed amount is 0");
        B.xr.repayRemoteBorrow(alice, owed, address(B.market), EID_A);

        vm.expectRevert("Borrowed amount is 0");
        B.xr.repayRemoteBorrow(
            alice,
            type(uint256).max,
            address(B.market),
            EID_A
        );

        vm.expectRevert("Borrowed amount is 0");
        B.xr.repayRemoteBorrow(alice, 1e18, address(B.market), EID_A);
        vm.stopPrank();

        assertEq(
            B.store.getForeignBackedLoans(alice, address(B.usdc)).length,
            1
        );
        assertEq(A.store.getOutboundLoans(alice, address(A.usdc)).length, 1);
    }

    function test_thirdPartyCannotRepayForAlice() public {
        _borrowCross(alice, 5_000e18);

        _fund(B, bob, 5_000e18);
        vm.prank(bob);
        vm.expectRevert("Borrowed amount is 0");
        B.xr.repayRemoteBorrow(alice, 1_000e18, address(B.market), EID_A);
    }

    function test_debtGrowsUntilCollateralIsNotEnough() public {
        _borrowCross(alice, 5_000e18);

        (uint256 borrowed, uint256 collateral) = A.store.accountPosition(
            alice,
            address(A.market),
            0
        );
        assertLt(borrowed, collateral);

        skip(20 * 365 days);

        (borrowed, collateral) = A.store.accountPosition(
            alice,
            address(A.market),
            0
        );
        assertGt(borrowed, collateral);

        // still unrepayable
        B.usdc.mint(alice, borrowed);
        vm.startPrank(alice);
        B.usdc.approve(address(B.core), type(uint256).max);
        vm.expectRevert("Borrowed amount is 0");
        B.xr.repayRemoteBorrow(
            alice,
            type(uint256).max,
            address(B.market),
            EID_A
        );
        vm.stopPrank();
    }
}
