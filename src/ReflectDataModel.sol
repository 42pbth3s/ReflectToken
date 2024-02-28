// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

uint256 constant CHUNK_SIZE = 20;
uint256 constant FEE_TIRES = 8;

//This index pointers only mainted to give ability drop records from main index below
struct AccountTireIndex {
    uint24 indexId;
    uint8 tireIdInvert; //default is 0 -> uintX.max
    uint16 chunkIdInvert; 
}

struct AccountState {
    uint256 balanceBase;
    uint32 lastRewardId;
    bool isHighReward;

    AccountTireIndex[2] tirePoitnters;
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