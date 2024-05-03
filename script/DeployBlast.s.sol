// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { CompatSwapRouter } from "../src/CompatSwapRouter.sol";

contract DeployBlastScript is Script {
    CompatSwapRouter public router;

    address public orbit = 0x42E12D42b3d6C4A74a88A61063856756Ea2DB357;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // address CROCSWAPDEX = vm.envAddress("CROCSWAPDEX");
        // uint256 POOLIDX = vm.envUint("POOLIDX");
        address CROCSWAPDEX = 0xaAaaaAAAFfe404EE9433EEf0094b6382D81fb958;
        uint256 POOLIDX = 420;

        router = new CompatSwapRouter(CROCSWAPDEX, POOLIDX);
        router.updateWeirdTokenMaxAllowance(orbit, type(uint96).max);
    }
}
