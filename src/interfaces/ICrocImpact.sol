// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

interface ICrocImpact {
    function calcImpact(address base, address quote, uint256 poolIdx, bool isBuy, bool inBaseQty, uint128 qty, uint16 poolTip, uint128 limitPrice)
        external
        view
        returns (int128 baseFlow, int128 quoteFlow, uint128 finalPrice);

    function dex_() external view returns (address);
}
