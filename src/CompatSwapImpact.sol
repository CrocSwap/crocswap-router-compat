// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import "./interfaces/ICompatSwapImpact.sol";
import "./interfaces/ICrocImpact.sol";
import "./libraries/Path.sol";
import "./libraries/TickMath.sol";

error ReceivedEtherOutsideSwap();
error NegativeOutput(int128);
error InsufficientOutput(uint256);

/// @title A Uniswap Swap Router compatible impact calculator for Ambient
/// @author strobie <strobie@crocodilelabs.io>
contract CompatSwapImpact is ICompatSwapImpact {
    using Path for bytes;

    ICrocImpact immutable impact_;
    uint256 immutable poolIdx_;

    /* //////////////////////////////////////////////////
    ////////////         CONSTRUCTOR          ///////////
    ////////////////////////////////////////////////// */

    constructor(address impact, uint256 poolIdx) {
        impact_ = ICrocImpact(impact);
        poolIdx_ = poolIdx;
    }

    /* //////////////////////////////////////////////////
    ////////////           FALLBACK           ///////////
    ////////////////////////////////////////////////// */

    /// @notice Fallback function to reject ether outside of swaps, since this contract is not meant to hold money
    receive() external payable {
        revert ReceivedEtherOutsideSwap();
    }

    /* //////////////////////////////////////////////////
    ////////////       PRIVATE FUNCTIONS      ///////////
    ////////////////////////////////////////////////// */

    function execSwapExactInput(address base, address quote, uint256 poolIdx, bool isBuy, bool inBaseQty, uint128 qty, uint16 tip, uint128 limitPrice, uint128)
        private
        view
        returns (int128 baseFlow, int128 quoteFlow)
    {
        (baseFlow, quoteFlow,) = impact_.calcImpact(base, quote, poolIdx, isBuy, inBaseQty, qty, tip, limitPrice);
    }

    /* //////////////////////////////////////////////////
    ////////////        PUBLIC FUNCTIONS      ///////////
    ////////////////////////////////////////////////// */

    /// @inheritdoc ICompatSwapImpact
    function exactInputSingle(ExactInputSingleParams calldata params) external view override returns (uint256 amountOut) {
        (address base, address quote) = params.tokenIn < params.tokenOut ? (params.tokenIn, params.tokenOut) : (params.tokenOut, params.tokenIn);
        bool isBaseIn = params.tokenIn == base;

        uint128 qty = uint128(params.amountIn);

        (int128 baseFlow, int128 quoteFlow) = execSwapExactInput(
            base,
            quote,
            poolIdx_,
            isBaseIn,
            isBaseIn,
            qty,
            0,
            params.sqrtPriceLimitX64 == 0 ? (isBaseIn ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1) : params.sqrtPriceLimitX64,
            0
        );
        int128 outFlow = isBaseIn ? -quoteFlow : -baseFlow;
        if (outFlow < 0) revert NegativeOutput(outFlow);
        amountOut = uint256(int256(outFlow));
    }

    /// @inheritdoc ICompatSwapImpact
    function exactInput(ExactInputParams memory params) external view override returns (uint256) {
        bytes memory path = params.path;
        (address tokenIn, address tokenOut) = path.decodeFirstPool();

        address tokenOut_ = tokenOut;
        (address base, address quote) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        bool isBaseIn = tokenIn == base;
        uint128 qty = uint128(params.amountIn);

        (int128 baseFlow, int128 quoteFlow) =
            execSwapExactInput(base, quote, poolIdx_, isBaseIn, isBaseIn, qty, 0, isBaseIn ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1, 0);
        int128 outFlow = isBaseIn ? -quoteFlow : -baseFlow;
        if (outFlow < 0) revert NegativeOutput(outFlow);
        qty = uint128(uint256(int256(outFlow)));

        if (path.hasMultiplePools()) {
            path = path.skipToken();
            uint256 numPoolsLeft = path.numPools();

            for (uint256 i = 0; i < numPoolsLeft; i++) {
                (tokenIn, tokenOut) = path.decodeFirstPool();
                (base, quote) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
                isBaseIn = tokenIn == base;
                (baseFlow, quoteFlow) = execSwapExactInput(
                    base, quote, poolIdx_, isBaseIn, isBaseIn, qty, 0, isBaseIn ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1, 0
                );
                outFlow = isBaseIn ? -quoteFlow : -baseFlow;
                if (outFlow < 0) revert NegativeOutput(outFlow);
                qty = uint128(uint256(int256(outFlow)));
                tokenOut_ = isBaseIn ? quote : base;
                path = path.skipToken();
            }
        }

        return qty;
    }
}
