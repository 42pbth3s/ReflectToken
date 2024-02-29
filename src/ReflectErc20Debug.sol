// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectErc20.sol";

contract ReflectDebug is Reflect {
    constructor (uint16 tax, uint16 share1, address taxAuth1, address taxAuth2) 
        Reflect(tax, share1, taxAuth1, taxAuth2)
    {

    }


    function LastShadowIndexedTireInvert() public view returns(uint8) {
        return _lastShadowIndexedTireInvert;
    }

    function LastShadowIndexedChunkInvert() public view returns(uint16) {
        return _lastShadowIndexedChunkInvert;
    }

    function NextAirdropRoot() public view returns(bytes32) {
        return _nextAirdropRoot;
    }
    function NextAirdrop() public view returns(uint256) {
        return _nextAirdrop;
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


    function DebugAppendAccountToMintIndex(uint256 mintIndexId, uint8 tireId, address wallet) public {
        _appendAccountToMintIndex(MintIndexes[mintIndexId], tireId, wallet);
    }

    function DebugDropAccountFromMintIndex(uint256 mintIndexId, address wallet, uint8 tireId, uint256 chunkId) public {
        _dropAccountFromMintIndex(MintIndexes[mintIndexId], wallet, tireId, chunkId);
    }

    function DebugBoostWalletCore(address wallet) public onlyOwner {
        _accounts[wallet].isHighReward = true;

    }
}