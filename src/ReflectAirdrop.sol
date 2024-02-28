// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./ReflectDataModel.sol";
import {ReflectTireIndex} from "./ReflectTireIndex.sol";

abstract contract ReflectAirdrop is ReflectTireIndex {

    constructor () {
        _nextAirdropRoot = bytes32(type(uint256).max);
    }
    
    function _shadowMintIndexEnabled() internal override view returns (bool) {
        return _nextAirdropRoot != bytes32(type(uint256).max);
    }


    function PrepareAirdrop(bytes32 root, uint256 totalAmount, uint256 gasLimit) public onlyOwner {
        require(root != bytes32(type(uint256).max), "Invalid root has been supplied");
        require(_nextAirdropRoot == bytes32(type(uint256).max), "Airdrop already launched");
        require(!RegistredAirdrop[root], "This airdrop has already been registred");
        require(totalAmount > 0, "Airdrop shall be positive");

        _nextAirdropRoot = root;
        _nextAirdrop = totalAmount;
        
        if (root != bytes32(uint256(1)))
            RegistredAirdrop[root] = true;

        uint256 activeMintIndex = ActiveMintIndex;
        uint256 nextTotalSupply = MintIndexes[activeMintIndex].totalSupply;
        uint256 availableBalance = _accounts[AvailableMintAddress()].balanceBase;
        
        if (availableBalance < totalAmount) {
            nextTotalSupply += totalAmount - availableBalance;
        }

        MintIndex storage newIndex = MintIndexes[activeMintIndex + 1];

        newIndex.totalSupply = nextTotalSupply;

        for (uint256 i = 0; i < FEE_TIRES; i++) {
            (newIndex.tires[i].regularLength, newIndex.tires[i].highLength, newIndex.tires[i].chunksCount) = 
                (0, 0, 0);
        }

        _lastShadowIndexedTireInvert = type(uint8).max; // not 0; gas saving
        _lastShadowIndexedChunkInvert = type(uint16).max; // not 0; gas saving

        IndexShadow(gasLimit);
    }

    function IndexShadow(uint256 gasLimit) public onlyOwner {
        uint8 tire = ~_lastShadowIndexedTireInvert;
        uint16 chunkId = ~_lastShadowIndexedChunkInvert;

        uint256 activeMintIndex = ActiveMintIndex;
        uint256 shadowMintIndex = activeMintIndex + 1;
        uint256 shadowTotalSupply = MintIndexes[shadowMintIndex].totalSupply;

        for (; (tire < FEE_TIRES) && (gasleft() > gasLimit); tire++) {
            uint32 tireChunksCount = MintIndexes[activeMintIndex].tires[tire].chunksCount;

            for (; (chunkId < tireChunksCount) && (gasleft() > gasLimit); chunkId++) {
                
                IndexChunk memory chunk = MintIndexes[activeMintIndex].tires[tire].chunks[chunkId];

                for (uint256 i = 0; i < CHUNK_SIZE; i++) {
                    
                    //balanceOf must never user current reward cycle!
                    uint256 balance = balanceOfWithUpdate(chunk.list[i]);

                    (uint8 newTire, bool tireFound) = _getIndexTireByBalance(balance, shadowTotalSupply);

                    if (tireFound) {
                        uint256 chunkIndex = _appendAccountToMintIndex(MintIndexes[shadowMintIndex], newTire, chunk.list[i]);

                        AccountTireIndex storage shadowTireAccIdx = _getAccountTireShadowIndex(chunk.list[i]);

                        (
                            shadowTireAccIdx.indexId, 
                            shadowTireAccIdx.tireIdInvert, 
                            shadowTireAccIdx.chunkIdInvert
                        ) =
                            (uint24(shadowMintIndex), ~newTire, ~uint16(chunkIndex));
                    }
                }
            }

            if (chunkId == tireChunksCount) {
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
        require(nextAirdropRoot != bytes32(uint256(1)), "This airdrop for targted users. You cannot launch public one!");

        
        //Activating new index
        uint24 newMint = ++ActiveMintIndex;        
        uint256 currentRewardCycle = CurrentRewardCycle;
        RewardCycles[currentRewardCycle].mintIndex = newMint;
       
        //Activating airdrop
        uint256 nextAirdrop = _nextAirdrop;
        uint256 availableBalance = _accounts[AvailableMintAddress()].balanceBase;

        if (availableBalance > 0) {
            if (availableBalance > nextAirdrop) {
                availableBalance -= nextAirdrop;
                _accounts[AvailableMintAddress()].balanceBase = availableBalance;
            } else {
                _accounts[AvailableMintAddress()].balanceBase = 0;
            }
        }
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


    function MintTo(address wallet) public onlyOwner {
        bytes32 nextAirdropRoot = _nextAirdropRoot;
        
        require(nextAirdropRoot != bytes32(type(uint256).max), "Airdrop must be prepared");
        require((~_lastShadowIndexedTireInvert) == FEE_TIRES, "You must initilize index first");
        require(nextAirdropRoot == bytes32(uint256(1)), "This is a public airdrop. You cannot do targeted one!");

        _nextAirdropRoot = bytes32(type(uint256).max);
        
        //Activating new index
        uint24 newMint = ++ActiveMintIndex;        
        uint256 currentRewardCycle = CurrentRewardCycle;
        RewardCycles[currentRewardCycle].mintIndex = newMint;

        //Activating airdrop
        uint256 nextAirdrop = _nextAirdrop;
        uint256 availableBalance = _accounts[AvailableMintAddress()].balanceBase;

        if (availableBalance > 0) {
            if (availableBalance > nextAirdrop) {
                availableBalance -= nextAirdrop;
                _accounts[AvailableMintAddress()].balanceBase = availableBalance;
            } else {
                _accounts[AvailableMintAddress()].balanceBase = 0;
            }
        }
        _accounts[LockedMintAddress()].balanceBase += nextAirdrop;

        _mint(wallet, nextAirdrop);
        
        _updateUserIndex(wallet, balanceOfWithUpdate(wallet));
    }


    function Airdrop(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(AirdropWaveRoots[root] >= amount, "Unrecognized airdrop or Airdrop has been stoped");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require(MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this airdrop or input is wrong");
        require(!ClaimedAirdrop[leaf], "Already claimed");

        ClaimedAirdrop[leaf] = true;
        _mint(msg.sender, amount);


        AirdropWaveRoots[root] -= amount;

        _updateUserIndex(msg.sender, balanceOfWithUpdate(msg.sender));
    }
}