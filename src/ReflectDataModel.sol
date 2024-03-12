// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

uint256 constant FEE_TIERS = 8;

struct AccountState {
    uint256 balance;
    bool isHighReward;
    bool excludedFromRewards;
}


struct RewardCycleStat {
    EnumerableSet.AddressSet regularUsers;
    EnumerableSet.AddressSet boostedUsers;
}


struct RewardCycle {
    uint96 taxedEth;
    uint32 lastConvertedTime;
    /*bool completed;
    uint8 lastTier;
    uint24 lastRegularWallet;
    uint24 lastBoostedWallet;//*/
    RewardCycleStat[FEE_TIERS] stat;
}