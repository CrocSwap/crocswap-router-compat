// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { CompatSwapImpact } from "../src/CompatSwapImpact.sol";

contract DeployScrollSwapImpactScript is Script {
    CompatSwapImpact public impact;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address CROCIMPACT = 0x6A699AB45ADce02891E6115b81Dfb46CAa5efDb9;
        uint256 POOLIDX = 420;

        impact = new CompatSwapImpact(CROCIMPACT, POOLIDX);
    }
}
