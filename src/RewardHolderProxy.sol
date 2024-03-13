// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;


import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract RewardHolderProxy is Ownable {
    constructor ()
        Ownable(msg.sender) {

    }


    function SendTokenBack(IERC20 token, uint256 amount) public onlyOwner {
        token.transfer(msg.sender, amount);
    }
}