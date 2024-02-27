// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import "./ReflectDataModel.sol";
import {ReflectTireIndex} from "./ReflectErc20Storage.sol";

abstract contract ReflectAirdrop is ReflectTireIndex {
    
    function _shadowMintIndexEnabled() internal override view returns (bool) {
        return _nextAirdropRoot != bytes32(type(uint256).max);
    }


    function PrepareAirdrop(bytes32 root, uint256 totalAmount, uint2556 gasLimit) public onlyOwner {
        require(root != bytes32(type(uint256).max), "Invalid root has been supplied");
        require(_nextAirdropRoot == bytes32(type(uint256).max), "Airdrop already launched");

        _nextAirdropRoot = root;
        _nextAirdrop = totalAmount;

        uint256 activeMintIndex = ActiveMintIndex;
        uint256 nextTotalSupply = MintIndexes[activeMintIndex].totalSupply;
        uint256 availableBalance = balanceOf(AvailableMintAddress());
        
        if (availableBalance < totalAmount) {
            nextTotalSupply += totalAmount - availableBalance;
        }

        MintIndex memory newIndex;

        newIndex.totalSupply = nextTotalSupply;

        for (uint256 i = 0; i < FEE_TIRES; i++) {
            newIndex.tires[i].length = 0;
        }

        MintIndexes[activeMintIndex + 1] = newIndex;
        _lastShadowIndexedTireInvert = type(uint8).max; // not 0; gas saving
        _lastShadowIndexedChunkInvert = type(uint16).max; // not 0; gas saving

        IndexShadow(gasLimit);
    }

    function IndexShadow(uint2556 gasLimit) public onlyOwner {
        uint8 tire = ~_lastShadowIndexedTireInvert;
        uint8 chunkId = ~_lastShadowIndexedChunkInvert;

        uint256 activeMintIndex = ActiveMintIndex;
        uint256 shadowMintIndex = activeMintIndex + 1;
        uint256 shadowTotalSupply = MintIndexes[shadowMintIndex].totalSupply;

        for (; (tire < FEE_TIRES) && (gasleft() > gasLimit); tire++) {
            IndexTire memory tireDesc = MintIndexes[activeMintIndex].tires[tire];

            for (; (chunkId < tireDesc.chunksCount) && (gasleft() > gasLimit); chunkId++) {
                
                IndexChunk memory chunk = MintIndexes[activeMintIndex].tires[tire].chunks[chunkId];

                for (uint256 i = 0; i < CHUNK_SIZE; i++) {
                    
                    //balanceOf must never user current reward cycle!
                    uint256 balance = balanceOfWithUpdate(chunk.list[i]);

                    (uint8 newTire, bool tireFound) = _getIndexTireByBalance(balance, shadowTotalSupply);

                    if (tireFound) {
                        uint256 chunkIndex = _appendAccountToMintIndex(MintIndexes[shadowMintIndex], newTire, chunk.list[i]);

                        (_accounts[chunk.list[i]].shadowIndexId, _accounts[chunk.list[i]].shadowIndexTire, _accounts[chunk.list[i]].shadowIndexChunk) =
                            (shadowMintIndex, newTire, uint16(chunkIndex));
                    }
                }
            }

            if (chunkId == tireDesc.chunksCount) {
                chunkId = 0;
            }
        }

        _lastShadowIndexedTireInvert = ~tire;
        _lastShadowIndexedChunkInvert = ~chunkId;
    }
    

    function LaunchAirdrop() public onlyOwner {
        bytes32 nextAirdropRoot = _nextAirdropRoot;
        
        require(nextAirdropRoot != bytes32(type(uint256).max), "Airdrop must be prepared");
        require((~_lastShadowIndexedTireInvert) == FEE_TIRES, "You must initilize index first");
        require(nextAirdropRoot != bytes32(1), "This airdrop for targted users. You cannot launch public one!");

        
        //Activating new index
        uint256 newMint = ++ActiveMintIndex;        
        uint256 currentRewardCycle = CurrentRewardCycle;

        //Updating reward stat
        for (uint256 i = 0; i < FEE_TIRES; i++) {
            IndexTire memory tireDesc = MintIndexes[newMint].tires[i];

            (RewardCycles[currentRewardCycle].rewardRecievers[i], RewardCycles[currentRewardCycle].highRewardRecievers[i]) = 
                (tireDesc.regularLength, tireDesc.highLength);
        }

        //Activating airdrop
        uint256 nextAirdrop = _nextAirdrop;
        //TODO: check out available and suck it out
        _accounts[LockedMintAddress()].balanceBase += nextAirdrop;
        AirdropWaveRoots[nextAirdropRoot] = nextAirdrop;

        _nextAirdropRoot = bytes32(type(uint256).max);
    }

    function StopAirdrop(bytes32 root) public onlyOwner {
        uint256 remaining = AirdropWaveRoots[root];

        AirdropWaveRoots[root] = 0;

        AccountState storage lockedAcc = _accounts[LockedMintAddress()];
        AccountState storage availableAcc = _accounts[AvailableMintAddress()];

        lockedAcc.balanceBase -= remaining;
        availableAcc.balanceBase += remaining;
    }


    function Airdrop(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(AirdropWaveRoots[root] >= amount, "Unrecognized airdrop or Airdrop has been stoped");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require(MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this airdrop or input is wrong");
        require(!ClaimedAirdrop[leaf], "Already claimed");

        ClaimedAirdrop[leaf] = true;
        _mint(msg.sender, amount);


        AirdropWaveRoots[nextAirdropRoot] -= amount;

        _updateUserIndex(msg.sender, balanceOfWithUpdate(wallet));
    }


    function MintTo(address wallet) public onlyOwner {
        bytes32 nextAirdropRoot = _nextAirdropRoot;
        
        require(nextAirdropRoot != bytes32(type(uint256).max), "Airdrop must be prepared");
        require((~_lastShadowIndexedTireInvert) == FEE_TIRES, "You must initilize index first");
        require(nextAirdropRoot == bytes32(1), "This is a public airdrop. You cannot do targeted one!");

        _nextAirdropRoot = bytes32(type(uint256).max);
        
        //Activating new index
        uint256 newMint = ++ActiveMintIndex;        
        uint256 currentRewardCycle = CurrentRewardCycle;

        //Updating reward stat
        for (uint256 i = 0; i < FEE_TIRES; i++) {
            IndexTire memory tireDesc = MintIndexes[newMint].tires[i];

            (RewardCycles[currentRewardCycle].rewardRecievers[i], RewardCycles[currentRewardCycle].highRewardRecievers[i]) = 
                (tireDesc.regularLength, tireDesc.highLength);
        }

        //Activating airdrop
        uint256 nextAirdrop = _nextAirdrop;
        //TODO: check out available and suck it out
        _accounts[LockedMintAddress()].balanceBase += nextAirdrop;

        _mint(wallet, nextAirdrop);
        
        _updateUserIndex(wallet, balanceOfWithUpdate(wallet));
    }
}