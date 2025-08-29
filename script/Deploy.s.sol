// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Marketplace.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        new Marketplace(500, payable(0x90F79bf6EB2c4f870365E785982E1f101E93b906));
        vm.stopBroadcast();
    }
}
