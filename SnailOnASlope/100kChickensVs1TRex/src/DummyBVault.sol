// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {FeeLib} from "./FeeLib.sol";
import {MockOracle} from "./MockOracle.sol";

contract DummyBVault is ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint256 internal constant RAY = 1e27;

    MockOracle public immutable oracle;
    address public insuranceFund;
    FeeLib.FeeData public feeData;

    mapping(address => bool) public supported;
    mapping(address => uint256) public totalSupplies;
    mapping(address => bool) public whitelist;

    error AssetNotSupported(address asset);
    error Slippage(uint256 amountOut, uint256 minAmountOut);

    constructor(
        MockOracle _oracle,
        address _insuranceFund,
        address[] memory _assets,
        FeeLib.FeeData memory _feeData
    ) ERC20("Bozhidar USD", "bUSD") Ownable(msg.sender) {
        oracle = _oracle;
        insuranceFund = _insuranceFund;
        feeData = _feeData;
        for (uint256 i; i < _assets.length; ++i) {
            supported[_assets[i]] = true;
        }
    }

    function setWhitelist(address user, bool status) external onlyOwner {
        whitelist[user] = status;
    }

    function mint(
        address asset,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 amountOut, uint256 fee) {
        return _mintWithCurve(asset, amountIn, minAmountOut, receiver, false);
    }

    // For testing purposes, trying the Simpson's rule
    function mintAveraged(
        address asset,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 amountOut, uint256 fee) {
        return _mintWithCurve(asset, amountIn, minAmountOut, receiver, true);
    }

    function quoteMint(
        address asset,
        uint256 amountIn,
        bool averaged
    ) external view returns (uint256 amountOut, uint256 fee) {
        return _quote(asset, amountIn, averaged);
    }

    function _mintWithCurve(
        address asset,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bool averaged
    ) internal returns (uint256 amountOut, uint256 fee) {
        (amountOut, fee) = _quote(asset, amountIn, averaged);
        if (amountOut < minAmountOut) revert Slippage(amountOut, minAmountOut);

        totalSupplies[asset] += amountIn;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amountIn);

        _mint(receiver, amountOut);
        if (fee > 0) _mint(insuranceFund, fee);
    }

    function _quote(
        address asset,
        uint256 amountIn,
        bool averaged
    ) internal view returns (uint256 amountOut, uint256 fee) {
        if (!supported[asset]) revert AssetNotSupported(asset);

        (
            uint256 oldRatio,
            uint256 midRatio,
            uint256 newRatio,
            uint256 grossOut
        ) = _ratios(asset, amountIn);

        if (whitelist[msg.sender]) return (grossOut, 0);

        uint256 rate = FeeLib.mintRate(feeData, newRatio);
        if (averaged) {
            // Proposed fix with Simpson's rule for testing pruposes
            rate =
                (FeeLib.mintRate(feeData, oldRatio) +
                    4 *
                    FeeLib.mintRate(feeData, midRatio) +
                    rate) /
                6;
        }

        fee = (grossOut * rate) / RAY;
        amountOut = grossOut - fee;
    }

    function _ratios(
        address asset,
        uint256 amountIn
    )
        internal
        view
        returns (
            uint256 oldRatio,
            uint256 midRatio,
            uint256 newRatio,
            uint256 grossOut
        )
    {
        uint256 capPrice = oracle.price(address(this));
        uint256 capUnit = 10 ** decimals();

        uint256 assetValue = (amountIn * oracle.price(asset)) /
            (10 ** IERC20Metadata(asset).decimals());
        uint256 allocationValue = (totalSupplies[asset] * oracle.price(asset)) /
            (10 ** IERC20Metadata(asset).decimals());
        uint256 capValue = (totalSupply() * capPrice) / capUnit;

        grossOut = (assetValue * capUnit) / capPrice;

        if (totalSupply() != 0) {
            oldRatio = (allocationValue * RAY) / capValue;
            midRatio =
                ((allocationValue + assetValue / 2) * RAY) /
                (capValue + assetValue / 2);
            newRatio =
                ((allocationValue + assetValue) * RAY) /
                (capValue + assetValue);
        }
    }
}
