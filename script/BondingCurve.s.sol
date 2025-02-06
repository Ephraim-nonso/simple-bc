import {Script} from "forge-std/Script.sol";
// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {BondingCurve} from "../src/BondingCurve.sol";

contract BondingCurveScript is Script {
    address ROUTER = 0xdF67507DF7C1553a4071F2e2D03e88a7E31e97C7;
    address FACTORY = 0xbA33af385BCDf660203F4a8F51A5e83Ac9a56fb5;
    address TREASURY = 0x00cB231aB0d44BB6eEBCb8d7b4a69B3aeBFFdCd5;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new BondingCurve(ROUTER, FACTORY, TREASURY);
        vm.stopBroadcast();
    }
}
