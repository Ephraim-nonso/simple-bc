import {Script, console} from "forge-std/Script.sol";
// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {Pool} from "../lib/superchain-contracts/src/pools/Pool.sol";
import {PoolFactory} from "../lib/superchain-contracts/src/pools/PoolFactory.sol";
import {Router} from "../lib/superchain-contracts/src/Router.sol";

contract ExchangeCurveScript is Script {
    address ROUTER = 0x545B2619DeD5A084F505a86BD2d4CeCDe62224ea;
    address FACTORY = 0x53FE982c40C560B84Ab7F89e51F033519781D99e;
    address ADMIN = 0x00cB231aB0d44BB6eEBCb8d7b4a69B3aeBFFdCd5;
    address WETH = 0x4200000000000000000000000000000000000006;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying the pool implementation");
        Pool poolImpl = new Pool();
        console.log("Deploying the pool factory");
        PoolFactory factory = new PoolFactory(
            address(poolImpl),
            0x00cB231aB0d44BB6eEBCb8d7b4a69B3aeBFFdCd5,
            0x00cB231aB0d44BB6eEBCb8d7b4a69B3aeBFFdCd5,
            0x00cB231aB0d44BB6eEBCb8d7b4a69B3aeBFFdCd5
        );
        console.log("Deploying the pool router");
        new Router(address(factory), WETH);

        vm.stopBroadcast();
    }
}
