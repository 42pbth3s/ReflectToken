// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

uint256 constant FEE_TIRES = 8;

struct AccountState {
    uint256 balanceBase;
    uint32 lastRewardId;
    bool isHighReward;
    bool excludedFromRewards;
}


struct RewardCycleStat {
    uint32 regularMembers;
    uint32 boostedMembers;
}

struct RewardCycle {
    uint96 taxed;
    RewardCycleStat[FEE_TIRES] stat;
}