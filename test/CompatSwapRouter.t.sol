// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { CompatSwapRouter } from "../src/CompatSwapRouter.sol";
import { ICompatSwapRouter } from "../src/interfaces/ICompatSwapRouter.sol";
import { IERC20Minimal } from "../src/interfaces/IERC20Minimal.sol";

contract CompatSwapRouterTest is Test {
    uint256 blastFork;
    CompatSwapRouter public router;
    address public usdb = 0x4300000000000000000000000000000000000003;
    address public orbit = 0x42E12D42b3d6C4A74a88A61063856756Ea2DB357;
    address public ezeth = 0x2416092f143378750bb29b79eD961ab195CcEea5;
    address public mim = 0x76DA31D7C9CbEAE102aff34D3398bC450c8374c1;

    address public user = address(69);

    function setUp() public {
        blastFork = vm.createFork("https://rpc.blast.io");
        vm.selectFork(blastFork);

        vm.deal(user, 10000 ether);
        vm.startPrank(user);

        router = new CompatSwapRouter(0xaAaaaAAAFfe404EE9433EEf0094b6382D81fb958, 420);
        router.updateWeirdTokenMaxAllowance(orbit, type(uint96).max);

        IERC20Minimal(usdb).approve(address(router), 100000000 ether);

        // console.log("eth balance before anything: ", address(user).balance);
        // console.log("usdb balance before anything: ", IERC20Minimal(usdb).balanceOf(user));
    }

    function test_ExactInputSingle_ETH() public {
        uint256 output = router.exactInputSingle{ value: 1 ether }(
            ICompatSwapRouter.ExactInputSingleParams({
                tokenIn: address(0),
                tokenOut: usdb,
                recipient: user,
                deadline: block.timestamp + 1000,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX64: 0
            })
        );
        // console.log("eth balance after everything: ", address(user).balance);
        // console.log("usdb balance after anything: ", IERC20Minimal(usdb).balanceOf(user));

        assertEq(9999 ether, address(user).balance);
        assertGt(output, 0);
        assertEq(output, IERC20Minimal(usdb).balanceOf(user));
    }

    function testFail_ExactInput_BadLimit() public {
        router.exactInput{ value: 1 ether }(
            ICompatSwapRouter.ExactInputParams({
                path: abi.encodePacked(address(0), usdb),
                recipient: user,
                deadline: block.timestamp + 1000,
                amountIn: 1 ether,
                amountOutMinimum: 1000000000 ether
            })
        );
    }

    function test_ExactInput_ButSingleETH() public {
        uint256 output = router.exactInput{ value: 1 ether }(
            ICompatSwapRouter.ExactInputParams({
                path: abi.encodePacked(address(0), usdb),
                recipient: user,
                deadline: block.timestamp + 1000,
                amountIn: 1 ether,
                amountOutMinimum: 0
            })
        );
        // console.log("eth balance after everything: ", address(user).balance);
        // console.log("usdb balance after anything: ", IERC20Minimal(usdb).balanceOf(user));

        assertEq(9999 ether, address(user).balance);
        assertGt(output, 0);
        assertEq(output, IERC20Minimal(usdb).balanceOf(user));
        assertEq(0, address(router).balance);
        assertEq(0, IERC20Minimal(usdb).balanceOf(address(router)));
    }

    function test_ExactInput_Multihop() public {
        uint256 output = router.exactInput{ value: 0.1 ether }(
            ICompatSwapRouter.ExactInputParams({
                path: abi.encodePacked(address(0), orbit, address(0), usdb, mim),
                recipient: user,
                deadline: block.timestamp + 1000,
                amountIn: 0.1 ether,
                amountOutMinimum: 0
            })
        );

        assertEq(9999.9 ether, address(user).balance);
        assertEq(0, IERC20Minimal(usdb).balanceOf(user));
        assertEq(0, IERC20Minimal(orbit).balanceOf(user));
        assertGt(output, 0);
        assertEq(output, IERC20Minimal(mim).balanceOf(user));

        assertEq(0, address(router).balance);
        assertEq(0, IERC20Minimal(usdb).balanceOf(address(router)));
        assertEq(0, IERC20Minimal(orbit).balanceOf(address(router)));
        assertEq(0, IERC20Minimal(mim).balanceOf(address(router)));
    }
}
