// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILendingProtocol {
    function claimFees(
        address token,
        address receiver
    ) external returns (uint256);
}

contract ActionRouter {
    IERC20 public immutable lpt;
    ILendingProtocol public immutable lendingProtocol;
    address public actionVault;
    bool public actionVaultInitialized;

    mapping(address => bool) public whitelistedTokens;

    // Fake exchange rate
    // 1 USDC fee -> 2 LPT
    // 1 DAI fee  -> 1 LPT
    // Values use 1e18 precision for simplicity
    mapping(address => uint256) public lptPerToken;

    constructor(address _lpt, address _lendingProtocol) {
        lpt = IERC20(_lpt);
        lendingProtocol = ILendingProtocol(_lendingProtocol);
    }

    function whitelistToken(address token, uint256 exchangeRate) external {
        whitelistedTokens[token] = true;
        lptPerToken[token] = exchangeRate;
    }

    function setActionVault(address _actionVault) external {
        require(!actionVaultInitialized, "Already initialized");

        actionVault = _actionVault;
        actionVaultInitialized = true;
    }

    // Sweep all fees for the specified tokens
    function sweepFees(address[] calldata tokens) external {
        _sweepFees(tokens, true, true);
    }

    function _sweepFees(
        address[] calldata tokens,
        bool fromBorrow,
        bool fromSupply
    ) internal {
        uint256 totalLPT;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            require(whitelistedTokens[token], "token must be whitelisted");

            uint256 fees;

            if (fromBorrow) {
                // Dummy implementation: borrow fees omitted.
            }

            if (fromSupply) {
                fees = lendingProtocol.claimFees(token, address(this));
            }

            if (fees > 0) {
                totalLPT += _fakeSwap(token, fees);
            }
        }

        _sendLPT(actionVault, totalLPT);
    }

    // Fake swap so we simply calculate how much LPT is the fee amount
    // The router must already have enough LPT funded for the demo
    function _fakeSwap(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 rate = lptPerToken[token];

        // Both amounts are assumed to have 18 decimals for simplicity
        return (amount * rate) / 1e18;
    }

    // Transfer LPT to receiver
    function _sendLPT(
        address receiver,
        uint256 amount
    ) internal returns (uint256) {
        uint256 lptBalance = lpt.balanceOf(address(this));

        if (amount > 0 && amount <= lptBalance) {
            require(lpt.transfer(receiver, amount), "LPT transfer failed");
            return 0;
        }

        return amount;
    }
}
