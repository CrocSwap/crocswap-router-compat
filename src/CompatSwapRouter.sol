// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import "./interfaces/ICompatSwapRouter.sol";
import "./interfaces/ICrocSwapDex.sol";
import "./libraries/Path.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TickMath.sol";
import "./libraries/Directives.sol";

error NotAuthorized();
error DeadlineExceeded();
error ReEntrant();
error ReceivedEtherOutsideSwap();
error NegativeOutput(int128);
error InsufficientOutput(uint256);

/// @title A Uniswap Swap Router compatible router for Ambient
/// @author strobie <strobie@crocodilelabs.io>
contract CompatSwapRouter is ICompatSwapRouter {
    using Path for bytes;

    address swapRecipient_;
    ICrocSwapDex immutable dex_;
    uint256 immutable poolIdx_;
    mapping(address => uint256) approvals_;

    /* //////////////////////////////////////////////////
    ////////////    PERMISSIONED METHODS    /////////////
    ////////////////////////////////////////////////// */

    // ORBIT on blast for example allows max uint96
    mapping(address => uint256) weirdTokenMaxAllowances_;
    address weirdTokenCurator_;

    function updateWeirdTokenMaxAllowance(address token, uint256 maxAllowance) external onlyCurator {
        weirdTokenMaxAllowances_[token] = maxAllowance;
    }

    function setApproval(address token, bool isApproved) external onlyCurator {
        approvals_[token] = isApproved ? 1 : 0;
    }

    modifier onlyCurator() {
        if (msg.sender != weirdTokenCurator_) revert NotAuthorized();
        _;
    }

    /* //////////////////////////////////////////////////
    ////////////     ASSERSION MODIFIERS     ////////////
    ////////////////////////////////////////////////// */

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        _;
    }

    modifier inSwap(address swapRecipient) {
        if (swapRecipient_ != address(0)) revert ReEntrant();
        swapRecipient_ = swapRecipient;
        _;
        swapRecipient_ = address(0);
    }

    /* //////////////////////////////////////////////////
    ////////////         CONSTRUCTOR          ///////////
    ////////////////////////////////////////////////// */

    constructor(address dex, uint256 poolIdx) {
        dex_ = ICrocSwapDex(dex);
        poolIdx_ = poolIdx;
        weirdTokenCurator_ = msg.sender;
    }

    /* //////////////////////////////////////////////////
    ////////////           RECEIVE()          ///////////
    ////////////////////////////////////////////////// */

    receive() external payable {
        if (swapRecipient_ == address(0)) revert ReceivedEtherOutsideSwap();
    }

    /* //////////////////////////////////////////////////
    ////////////       PRIVATE FUNCTIONS      ///////////
    ////////////////////////////////////////////////// */

    function preLoadTokens(address base, address quote, bool isBuy, bool inBaseQty, uint128 qty, uint128 minOut) private {
        bool baseSendToken = isBuy && base != address(0);
        bool quoteSendToken = !isBuy;
        uint256 qtySend = isBuy == inBaseQty ? qty : minOut;

        if (baseSendToken) {
            prepSellToken(base, qtySend);
        } else if (quoteSendToken) {
            prepSellToken(quote, qtySend);
        }
    }

    function prepSellToken(address token, uint256 qty) private {
        approveToken(token);
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), qty);
    }

    function approveToken(address token) private {
        if (token != address(0) && approvals_[token] == 0) {
            uint256 maxAllowance = weirdTokenMaxAllowances_[token] == 0 ? type(uint128).max : weirdTokenMaxAllowances_[token];
            IERC20Minimal(token).approve(address(dex_), maxAllowance);
            approvals_[token] = 1;
        }
    }

    function execSwapExactInput(
        address base,
        address quote,
        uint256 poolIdx,
        bool isBuy,
        bool inBaseQty,
        uint128 qty,
        uint16 tip,
        uint128 limitPrice,
        uint128 minOut
    ) private returns (int128 baseFlow, int128 quoteFlow) {
        bytes memory swapCall = abi.encode(base, quote, poolIdx, isBuy, inBaseQty, qty, tip, limitPrice, minOut, 0x0);

        bytes memory result;
        if (base == address(0) && isBuy && inBaseQty) {
            result = dex_.userCmd{ value: qty }(1, swapCall);
        } else {
            // using ETH as input but not specifying amounts will automatically fail
            result = dex_.userCmd(1, swapCall);
        }

        (baseFlow, quoteFlow) = abi.decode(result, (int128, int128));
    }

    function settleTokens(address base, address quote) private returns (uint256 baseBal, uint256 quoteBal) {
        (baseBal, quoteBal) = (sendTokenBalance(base), sendTokenBalance(quote));
    }

    function sendTokenBalance(address token) private returns (uint256 balance) {
        if (token != address(0)) {
            balance = IERC20Minimal(token).balanceOf(address(this));
            if (balance > 0) {
                TransferHelper.safeTransfer(token, swapRecipient_, balance);
            }
        } else {
            balance = address(this).balance;
            if (balance > 0) {
                TransferHelper.safeEtherSend(swapRecipient_, balance);
            }
        }
    }

    /* //////////////////////////////////////////////////
    ////////////        PUBLIC FUNCTIONS      ///////////
    ////////////////////////////////////////////////// */

    /// @inheritdoc ICompatSwapRouter
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        inSwap(params.recipient)
        returns (uint256 amountOut)
    {
        (address base, address quote) = params.tokenIn < params.tokenOut ? (params.tokenIn, params.tokenOut) : (params.tokenOut, params.tokenIn);
        bool isBaseIn = params.tokenIn == base;

        uint128 qty = uint128(params.amountIn);
        uint128 minOut = uint128(params.amountOutMinimum);

        preLoadTokens(base, quote, isBaseIn, isBaseIn, qty, minOut);

        (int128 baseFlow, int128 quoteFlow) = execSwapExactInput(
            base,
            quote,
            poolIdx_,
            isBaseIn,
            isBaseIn,
            qty,
            0,
            params.sqrtPriceLimitX64 == 0 ? (isBaseIn ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1) : params.sqrtPriceLimitX64,
            minOut
        );
        int128 outFlow = isBaseIn ? -quoteFlow : -baseFlow;
        if (outFlow < 0) revert NegativeOutput(outFlow);
        amountOut = uint256(int256(outFlow));

        (uint256 baseBal, uint256 quoteBal) = settleTokens(base, quote);
        if (isBaseIn) {
            if (quoteBal < amountOut) revert InsufficientOutput(quoteBal);
        } else {
            if (baseBal < amountOut) revert InsufficientOutput(baseBal);
        }
    }

    /// @inheritdoc ICompatSwapRouter
    function exactInput(ExactInputParams memory params) external payable override checkDeadline(params.deadline) inSwap(params.recipient) returns (uint256) {
        bytes memory path = params.path;
        (address tokenIn, address tokenOut) = path.decodeFirstPool();

        address tokenIn_ = tokenIn;
        address tokenOut_ = tokenOut;
        (address base, address quote) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        bool isBaseIn = tokenIn == base;
        uint128 qty = uint128(params.amountIn);
        uint128 minOut = uint128(params.amountOutMinimum);

        preLoadTokens(base, quote, isBaseIn, isBaseIn, qty, minOut);
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
                approveToken(tokenIn);
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

        settleTokens(tokenIn_, tokenOut_);
        if (qty < minOut) revert InsufficientOutput(qty);
        return qty;
    }
}
