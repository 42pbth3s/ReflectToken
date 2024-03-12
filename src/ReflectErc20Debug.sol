// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";
import "./ReflectDataModel.sol";

contract ReflectDebug is Reflect {
    constructor (address teamWallet, uint256 tSupply) 
        Reflect(teamWallet, tSupply)
    {
    }

    
    function TierThresholds() public view returns(uint24[FEE_TIERS] memory) {
        return _tierThresholds;
    }
    function TierPortion() public view returns(uint16[FEE_TIERS] memory) {
        return _tierPortion;
    }

    function AccountData(address wallet) public view returns(AccountState memory) {
        return _accounts[wallet];
    }


    function DebugBoostWalletCore(address wallet) public onlyOwner {
        _accounts[wallet].isHighReward = true;
    }
    
    function _wethErc20() internal override pure returns(IERC20) {
        return IERC20(address(0));
    }

    function _uniV2Factory() internal override pure returns(IUniswapV2Factory) {
        return IUniswapV2Factory(address(0));
    }

    function _regularTax() internal override pure returns(uint256) {
        return 5_00;
    }
    function _highTax() internal override pure returns(uint256) {
        return 10_00;
    }
}