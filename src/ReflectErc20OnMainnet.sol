// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";
import "./ReflectDataModel.sol";

contract ReflectErc20OnMainnet is Reflect {
    constructor (address teamWallet, uint256 tSupply, uint256 airdropSupply) 
        Reflect(teamWallet, tSupply, airdropSupply)
    {

    }


    function _wethErc20() internal override pure returns(IERC20) {
        return IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    function _uniV2Factory() internal override pure returns(IUniswapV2Factory) {
        return IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    }

    function _regularTax() internal override pure returns(uint256) {
        return 5_00;
    }
    function _highTax() internal override pure returns(uint256) {
        return 10_00;
    }
}