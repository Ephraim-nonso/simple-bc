// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BondingToken is ERC20 {
    uint256 constant mint_amount = 1_000_000_000 * 10 ** 18;

    constructor(string memory tokenName, string memory tokenSymbol, address owner) ERC20(tokenName, tokenSymbol) {
        _mint(owner, mint_amount);
    }
}
