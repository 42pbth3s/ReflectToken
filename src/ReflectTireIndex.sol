// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import "./ReflectDataModel.sol";
import {ReflectErc20Core} from "./ReflectErc20Core.sol";


abstract contract ReflectTireIndex is ReflectErc20Core {
    
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
        uint8 newTire;
        bool tireFound;
        uint256 chunkId;
    }

    struct _userIndexState {
        uint256 oldTierId;
        uint256 oldChunkId;

        _userIndexTireState mainIndex;
        _userIndexTireState shadowIndex;
    }

    function _updateUserIndex(address wallet, uint256 balance) internal {
        MintIndex storage mIndex = MintIndexes[ActiveMintIndex];
        AccountState storage account = _accounts[wallet];
        uint256 oldTierId;
        uint256 oldChunkId;

        unchecked {
            oldTierId = ~uint256(account.mintIndexTireInvert);
            oldChunkId = ~uint256(account.mintIndexChunkInvert);
        }
        
        {
            (uint8 newTire, bool tireFound) = _getIndexTireByBalance(balance, mIndex.totalSupply);

            if (tireFound) {
                if (oldTierId != type(uint256).max) {
                    _dropAccountFromMintIndex(mIndex, wallet, uint8(oldTierId), oldChunkId);
                }

                uint256 chunkId = _appendAccountToMintIndex(mIndex, newTire, wallet);

                
                (account.mintIndexTireInvert, account.mintIndexChunkInvert) = 
                    (~newTire, ~uint16(chunkId));

            } else if (oldTierId != type(uint256).max) {
                _dropAccountFromMintIndex(mIndex, wallet, uint8(oldTierId), oldChunkId);

                (account.mintIndexTireInvert, account.mintIndexChunkInvert) = (0, 0);
            }
        }



        //Shall happen on very rare ocasions
        //if were not into index before - there is now way we will occur in shadow
        if ((oldTierId != type(uint256).max) && _shadowMintIndexEnabled()) {
            //TODO: Check that we're reached stage of main index

            uint8 lastShadowIndexedTire = ~_lastShadowIndexedTireInvert;
            uint16 lastShadowIndexedChunk = ~_lastShadowIndexedChunkInvert;

            //only if was indexed into shadow again - we need to go into it
            if (
                (oldTierId < lastShadowIndexedTire) ||
                ((oldTierId == lastShadowIndexedTire) && (oldChunkId < lastShadowIndexedChunk))
            ) {
                MintIndex storage shadowMIndex = MintIndexes[ActiveMintIndex + 1];
                AccountState storage accountCopy = account; //stack too deep

                (uint8 newShadowTire, bool shadowTireFound) = _getIndexTireByBalance(balance, shadowMIndex.totalSupply);

                if (shadowTireFound) {
                    {
                        uint256 oldShadowTierId = ~uint256(accountCopy.shadowIndexTireInvert);
                        
                        if (oldShadowTierId != type(uint256).max) {
                            uint256 oldShadowChunkId = ~uint256(accountCopy.shadowIndexChunkInvert);

                            _dropAccountFromMintIndex(shadowMIndex, wallet, uint8(oldShadowTierId), oldShadowChunkId);
                        }
                    }

                    uint256 shadowChunkId = _appendAccountToMintIndex(shadowMIndex, newShadowTire, wallet);

                    
                    (accountCopy.shadowIndexId, accountCopy.shadowIndexTireInvert, accountCopy.shadowIndexChunkInvert) = 
                        (ActiveMintIndex + 1, ~newShadowTire, ~uint16(shadowChunkId));

                } else if (accountCopy.shadowIndexTireInvert != 0) {
                    uint256 oldShadowTierId = ~uint256(accountCopy.shadowIndexTireInvert);
                    uint256 oldShadowChunkId = ~uint256(accountCopy.shadowIndexChunkInvert);

                    _dropAccountFromMintIndex(shadowMIndex, wallet, uint8(oldShadowTierId), oldShadowChunkId);
                    
                    (accountCopy.shadowIndexId, accountCopy.shadowIndexTireInvert, accountCopy.shadowIndexChunkInvert) = 
                        (ActiveMintIndex + 1, 0, 0);
                }
            }
        }
    }

}