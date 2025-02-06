import {Script} from "forge-std/Script.sol";
// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {BondingToken} from "../src/BToken.sol";

contract BTokenScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // "LiskTester" "LSKT" "0x7702D99FE7B6a49206f0df477b1C6fA104AcCf9f"
        new BondingToken("LiskTester", "LSKT", 0x7702D99FE7B6a49206f0df477b1C6fA104AcCf9f);
        vm.stopBroadcast();
    }
}
