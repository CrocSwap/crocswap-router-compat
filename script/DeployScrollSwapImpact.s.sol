// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { CompatSwapImpact } from "../src/CompatSwapImpact.sol";

contract DeployScrollSwapImpactScript is Script {
    CompatSwapImpact public impact;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address CROCIMPACT = 0xc2c301759B5e0C385a38e678014868A33E2F3ae3;
        uint256 POOLIDX = 420;

        impact = new CompatSwapImpact(CROCIMPACT, POOLIDX);
    }
}
