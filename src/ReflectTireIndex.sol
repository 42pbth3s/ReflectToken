// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectDataModel.sol";
import {ReflectErc20Core} from "./ReflectErc20Core.sol";

abstract contract ReflectTireIndex is ReflectErc20Core {

    function _getAccountTireMainIndex(address wallet) internal view returns (AccountTireIndex storage) {
        return _accounts[wallet].tirePoitnters[ActiveMintIndex % 2];
    }

    function _getAccountTireShadowIndex(address wallet) internal view returns (AccountTireIndex storage) {
        return _accounts[wallet].tirePoitnters[(ActiveMintIndex + 1) % 2];
    }
    
    
    function _getIndexTireByBalance(uint256 balance, uint256 totalSupply) internal view returns (uint8, bool) {        
        uint256 share = balance * TIRE_THRESHOLD_BASE / totalSupply;

        unchecked {
            for (uint256 j = 0; j < FEE_TIRES; j++) {
                if (share >= _tireThresholds[j]) {
                    return (uint8(j), true);
                }
            }
        }

        return (type(uint8).max, false);
    }


    function _appendAccountToMintIndex(MintIndex storage mIndex, uint8 tireId, address wallet) internal returns (uint256) {
        IndexTire storage tire = mIndex.tires[tireId];
        (uint32 tireRegularLength, uint32 tireHighLength, uint32 tireChunksCount) = 
            (tire.regularLength, tire.highLength, tire.chunksCount);

        if (_accounts[wallet].isHighReward)
            tireHighLength++;
        else
            tireRegularLength++;

        uint8 chunkLen = 0;
        uint256 chunkIndex = tireChunksCount;
        
        if (tireChunksCount > 0) {
            unchecked {
                uint8 testLen = tire.chunks[tireChunksCount - 1].length;
                if (testLen < CHUNK_SIZE) {
                    chunkIndex = tireChunksCount - 1;
                    chunkLen = testLen;
                }
            }
        } else {
            tireChunksCount = 1;
        }

        unchecked {
            tire.chunks[chunkIndex].list[chunkLen] = wallet;
            tire.chunks[chunkIndex].length = chunkLen + 1;

            (tire.regularLength, tire.highLength, tire.chunksCount) = 
                (tireRegularLength, tireHighLength, tireChunksCount);
        }
        return chunkIndex;
    }

    function _dropAccountFromMintIndex(MintIndex storage mIndex, address wallet, uint8 tireId, uint256 chunkId) internal {
        IndexTire storage tier = mIndex.tires[tireId];

        //Shall always pass
        require(chunkId < tier.chunksCount, "wrong chunk");

        IndexChunk storage chunk = tier.chunks[chunkId];
        uint256 chunkLen = chunk.length;

        for (uint256 i = 0; i < chunkLen; i++) {
            if (chunk.list[i] == wallet) {
                unchecked {
                    chunk.list[i] = chunk.list[chunkLen - 1];
                    chunk.length = uint8(chunkLen - 1);
                }

                if (_accounts[wallet].isHighReward)
                    tier.highLength--;
                else
                    tier.regularLength--;

                return;
            }
        }

        //Shall never happens
        require(false, "Nothing has been deleted");
    }
    struct _userIndexTireState {
        uint256 oldTierId;
        uint256 oldChunkId;
        uint8 newTire;
    }

    struct _userIndexState {
        _userIndexTireState mainIndex;
        _userIndexTireState shadowIndex;
    }

    function _updateUserIndex(address wallet, uint256 balance) internal {
        MintIndex storage mIndex = MintIndexes[ActiveMintIndex];
        AccountTireIndex storage accountMainTireIdx = _getAccountTireMainIndex(wallet);

        _userIndexState memory lState;

        unchecked {
            lState.mainIndex.oldTierId = uint256(~accountMainTireIdx.tireIdInvert);
            lState.mainIndex.oldChunkId = uint256(~accountMainTireIdx.chunkIdInvert);
        }
        
        {
            bool tireFound;
            (lState.mainIndex.newTire, tireFound) = _getIndexTireByBalance(balance, mIndex.totalSupply);

            if (tireFound) {
                if (lState.mainIndex.oldTierId != lState.mainIndex.newTire) 
                {
                    if (lState.mainIndex.oldTierId != type(uint8).max) {
                        _dropAccountFromMintIndex(mIndex, wallet, uint8(lState.mainIndex.oldTierId), lState.mainIndex.oldChunkId);
                    }

                    uint256 chunkId = _appendAccountToMintIndex(mIndex, lState.mainIndex.newTire, wallet);

                    
                    (accountMainTireIdx.tireIdInvert, accountMainTireIdx.chunkIdInvert) = 
                        (~lState.mainIndex.newTire, ~uint16(chunkId));
                }
            } else if (lState.mainIndex.oldTierId != type(uint8).max) {
                _dropAccountFromMintIndex(mIndex, wallet, uint8(lState.mainIndex.oldTierId), lState.mainIndex.oldChunkId);

                (accountMainTireIdx.tireIdInvert, accountMainTireIdx.chunkIdInvert) = (0, 0);
            }
        }



        //Shall happen on very rare ocasions
        if (_shadowMintIndexEnabled()) {
            uint8 lastShadowIndexedTire = ~_lastShadowIndexedTireInvert;
            uint16 lastShadowIndexedChunk = ~_lastShadowIndexedChunkInvert;

            //only if was indexed into shadow
            //   (indexing may happen acrros multiple txs) - we need to go into it again
            if (
                // in cases if we are/were present in main index
                (lState.mainIndex.oldTierId < lastShadowIndexedTire) ||
                (
                    (lState.mainIndex.oldTierId == lastShadowIndexedTire) && 
                    (lState.mainIndex.oldChunkId < lastShadowIndexedChunk)
                ) ||
                // in cases if we are just added in main index
                (lState.mainIndex.newTire < lastShadowIndexedTire)
            ) {
                uint24 shadowMintIndex = ActiveMintIndex + 1;
                MintIndex storage shadowMIndex = MintIndexes[shadowMintIndex];
                AccountTireIndex storage accountShadowTireIdx = _getAccountTireShadowIndex(wallet);

                bool shadowTireFound;
                (lState.shadowIndex.newTire, shadowTireFound) = _getIndexTireByBalance(balance, shadowMIndex.totalSupply);

                if (shadowTireFound) {
                    uint24 accountShadowMintIndex;                     
                    (accountShadowMintIndex, lState.shadowIndex.oldTierId) = 
                        (accountShadowTireIdx.indexId, uint256(~accountShadowTireIdx.tireIdInvert));

                    // only if change in tires or index outdated
                    if (
                        (lState.shadowIndex.oldTierId != lState.shadowIndex.newTire)  ||
                        (shadowMintIndex != accountShadowMintIndex)
                    ) {
                        //make sure that we're up to date, otherwise we can't drop nothing
                        // and we had been in index before
                        if (
                            (shadowMintIndex == accountShadowMintIndex) &&
                            (lState.shadowIndex.oldTierId != type(uint8).max)
                        ) {                            
                            lState.shadowIndex.oldChunkId = uint256(~accountShadowTireIdx.chunkIdInvert);

                            _dropAccountFromMintIndex(shadowMIndex, wallet, uint8(lState.shadowIndex.oldTierId), lState.shadowIndex.oldChunkId);
                        }
                        
                        uint256 shadowChunkId = _appendAccountToMintIndex(shadowMIndex, lState.shadowIndex.newTire, wallet);

                        
                        (accountShadowTireIdx.indexId, accountShadowTireIdx.tireIdInvert, accountShadowTireIdx.chunkIdInvert) = 
                            (shadowMintIndex, ~lState.shadowIndex.newTire, ~uint16(shadowChunkId));
                    }
                } else if (
                        (accountShadowTireIdx.tireIdInvert != 0) &&
                        (shadowMintIndex == accountShadowTireIdx.indexId) //make sure that we're indexed
                ) { 
                    uint256 oldShadowTierId = uint256(~accountShadowTireIdx.tireIdInvert);
                    uint256 oldShadowChunkId = uint256(~accountShadowTireIdx.chunkIdInvert);

                    _dropAccountFromMintIndex(shadowMIndex, wallet, uint8(oldShadowTierId), oldShadowChunkId);
                    
                    (accountShadowTireIdx.tireIdInvert, accountShadowTireIdx.chunkIdInvert) = 
                        (0, 0);
                }
            }
        }
    }

}