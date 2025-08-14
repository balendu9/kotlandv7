// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract kottoken is ERC20{
    constructor() ERC20("KOT", "KOT"){
         _mint(msg.sender,10000000000000*10**18);
    }
}