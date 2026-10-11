// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {BaseTest} from "./Base.t.sol";

contract RewardsBugTest is BaseTest {
    uint256 internal constant DAY_OF_REWARDS = 86_400e18;

    function test_borrowerExecutedHereEarnsNothing() public {
        _supply(A, alice, 10_000e18);
        _borrowCross(alice, 5_000e18);
        _fundRewards(B, 1_000_000e18);

        skip(1 days);
        B.market.updateBorrowRewardIndex();

        assertEq(B.market.totalPrincipal(), 5_000e18);
        assertApproxEqAbs(
            ((B.market.borrowRewardIndex() - 1e36) *
                B.market.totalPrincipal()) / 1e36,
            DAY_OF_REWARDS,
            1e6
        );

        _claim(B, alice);
        assertEq(B.tithe.balanceOf(alice), 0);
        assertEq(B.store.titheAccrued(alice), 0);
    }

    function test_halfOfTheEmissionVanishes() public {
        _supply(A, alice, 10_000e18);
        _supply(B, carol, 10_000e18);

        _borrowSame(B, carol, 5_000e18);
        _borrowCross(alice, 5_000e18);
        _fundRewards(B, 1_000_000e18);

        skip(1 days);
        _claim(B, carol);
        _claim(B, alice);

        assertApproxEqAbs(B.tithe.balanceOf(carol), DAY_OF_REWARDS / 2, 1e6);
        assertEq(B.tithe.balanceOf(alice), 0);
        assertApproxEqAbs(
            B.tithe.balanceOf(carol) + B.tithe.balanceOf(alice),
            DAY_OF_REWARDS / 2,
            1e6
        );
    }

    function test_phantomBorrowerDrainsRealBorrowersRewards() public {
        _supply(A, dave, 10_000e18);
        _borrowSame(A, dave, 5_000e18); // the only real debt in A

        _supply(A, bob, 10_000e18);
        _borrowCross(bob, 5_000e18); // Bob's debt is on B

        assertEq(A.market.totalPrincipal(), 5_000e18); // A only lent to Dave

        _fundRewards(A, DAY_OF_REWARDS);
        skip(1 days);

        _claim(A, bob);
        _claim(A, dave);

        assertApproxEqAbs(A.tithe.balanceOf(bob), DAY_OF_REWARDS, 1e6);
        assertEq(A.tithe.balanceOf(dave), 0);
        assertApproxEqAbs(A.store.titheAccrued(dave), DAY_OF_REWARDS, 1e6);

        assertApproxEqAbs(
            A.tithe.balanceOf(bob) + A.store.titheAccrued(dave),
            2 * DAY_OF_REWARDS,
            2e6
        );
    }

    function test_phantomRewardIsNotCappedByEmissions() public {
        _supply(A, dave, 10_000e18);
        _borrowSame(A, dave, 5_000e18);

        _supply(A, bob, 40_000e18);
        _borrowCross(bob, 20_000e18); // 4x the entire real debt of chain A

        _fundRewards(A, 10 * DAY_OF_REWARDS);
        skip(1 days);
        _claim(A, bob);

        assertApproxEqAbs(A.tithe.balanceOf(bob), 4 * DAY_OF_REWARDS, 1e7);
    }
}
