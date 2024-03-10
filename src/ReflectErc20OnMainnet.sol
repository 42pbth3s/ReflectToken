// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";
import "./ReflectDataModel.sol";

contract ReflectErc20OnMainnet is Reflect {
    constructor (uint16 tax, uint16 rewardShare, address teamWallet, uint256 tSupply) 
        Reflect(tax, rewardShare, teamWallet, tSupply)
    {

    }


    function _wethErc20() internal override pure returns(IERC20) {
        return IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    function _uniV2Factory() internal override pure returns(IUniswapV2Factory) {
        return IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    }
}