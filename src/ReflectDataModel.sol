// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

uint256 constant CHUNK_SIZE = 20;
uint256 constant FEE_TIRES = 8;

struct AccountState {
    uint256 balanceBase;
    uint32 lastRewardId;
    bool isHighReward;

    uint8 mintIndexTireInvert; //default is 0 -> uintX.max
    uint16 mintIndexChunkInvert;    

    uint24 shadowIndexId;
    uint8 shadowIndexTireInvert;
    uint16 shadowIndexChunkInvert;

}

struct IndexChunk {
    uint8 length; //TODO: drop it?
    address[CHUNK_SIZE] list;
}

struct IndexTire {
    uint32 regularLength;
    uint32 highLength;
    uint32 chunksCount;
    mapping(uint256 => IndexChunk) chunks;
}

struct MintIndex {
    uint256 totalSupply;
    IndexTire[FEE_TIRES] tires;
}

struct RewardCycle {
    uint96 taxed;
    uint24 mintIndex;
}