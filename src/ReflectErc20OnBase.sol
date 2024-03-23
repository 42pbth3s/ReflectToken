// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";
import "./ReflectDataModel.sol";

contract ReflectErc20OnBase is Reflect {
    constructor (address teamWallet, uint256 tSupply, uint256 airdropSupply) 
        Reflect(teamWallet, tSupply, airdropSupply)
    {

    }


    function _wethErc20() internal override pure returns(IERC20) {
        return IERC20(0x4200000000000000000000000000000000000006);
    }

    function _uniV2Factory() internal override pure returns(IUniswapV2Factory) {
        return IUniswapV2Factory(0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6);
    }

    function _regularTax() internal override pure returns(uint256) {
        return 5_00;
    }
    function _highTax() internal override pure returns(uint256) {
        return 10_00;
    }
}