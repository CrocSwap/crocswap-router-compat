// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { CompatSwapRouter } from "../src/CompatSwapRouter.sol";

contract DeployScrollScript is Script {
    CompatSwapRouter public router;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // address CROCSWAPDEX = vm.envAddress("CROCSWAPDEX");
        // uint256 POOLIDX = vm.envUint("POOLIDX");
        address CROCSWAPDEX = 0xaaaaAAAACB71BF2C8CaE522EA5fa455571A74106;
        uint256 POOLIDX = 420;

        router = new CompatSwapRouter(CROCSWAPDEX, POOLIDX);
    }
}
