// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";
import "./ReflectDataModel.sol";

contract ReflectDebug is Reflect {
    constructor (uint16 tax, uint16 share1, address taxAuth1, address taxAuth2, uint256 amount1, uint256 amount2, uint256 ownerAmount) 
        Reflect(tax, share1, taxAuth1, taxAuth2, amount1, amount2, ownerAmount)
    {

    }


    
    function TireThresholds() public view returns(uint24[FEE_TIRES] memory) {
        return _tireThresholds;
    }
    function TirePortion() public view returns(uint16[FEE_TIRES] memory) {
        return _tirePortion;
    }

    function AccountData(address wallet) public view returns(AccountState memory) {
        return _accounts[wallet];
    }


    function DebugBoostWalletCore(address wallet) public onlyOwner {
        _accounts[wallet].isHighReward = true;
    }

    function GetRewardCycleStat(uint256 rewcycle, uint256 tire) public view returns (RewardCycleStat memory) {
        return RewardCycles[rewcycle].stat[tire];
    }
}