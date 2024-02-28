// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./ReflectDataModel.sol";
import {ReflectTireIndex} from "./ReflectTireIndex.sol";
import {ReflectAirdrop} from "./ReflectAirdrop.sol";

contract Reflect is ReflectTireIndex, ReflectAirdrop {
    constructor (uint16 tax, uint16 share1, address taxAuth1, address taxAuth2)
        Ownable(msg.sender) {
        
        Tax = tax;
        TaxAuth1Share = share1;
        TaxAuthoriy1 = taxAuth1;
        TaxAuthoriy2 = taxAuth2;

           
        (_tireThresholds[0], _tireThresholds[1], _tireThresholds[2], _tireThresholds[3])=
            (1_0000, 7000, 3000, 900);

        (_tireThresholds[4], _tireThresholds[5], _tireThresholds[6], _tireThresholds[7]) =
            (600, 300, 90, 50);
        
        
        (_tirePortion[0], _tirePortion[1], _tirePortion[2], _tirePortion[3]) =
            (30_00, 23_00, 15_00, 11_00);

        (_tirePortion[4], _tirePortion[5], _tirePortion[6], _tirePortion[7]) = 
            (8_00, 6_00, 4_50, 2_50);
        
    }

    /********************************** GENERIC VIEW FUNCTIONs **********************************/



    /*################################# END - GENERIC VIEW FUNCTIONS #################################*/



    /********************************** CORE LOGIC **********************************/

    function balanceOf(address account) public override view returns (uint256) {
        (uint256 balance, ,) = _balanceWithRewards(account);
        return balance;
    }

    function balanceOfWithUpdate(address account) public override returns (uint256) {
        (uint256 balance, bool requireUpdate, uint256 rewarded) = _balanceWithRewards(account);

        if (requireUpdate) {
            (_accounts[account].balanceBase, _accounts[account].lastRewardId) = 
                (balance, CurrentRewardCycle);

            address taxAuth1 = TaxAuthoriy1;

            _accounts[taxAuth1].balanceBase -= rewarded;
            
            emit Transfer(taxAuth1, account, rewarded);
        }

        return balance;
    }

    
    function transfer(address to, uint256 value) public override returns (bool) {
        return _externalTransferCore(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool)  {
        _spendAllowance(from, msg.sender, value);

        return _externalTransferCore(from, to, value);
    }


    //++++++++++++++++++++++++++++++++ PRIVATE +++++++++++++++++++++

    struct _balanceState {
        uint256 resultBalance;
        bool needUpdate;
        uint256 rewarded;
        uint256 rewardCycle;
        bool highReward;
    }

    //This funcation assumes that balance hasn't been changed since last transfer happen
    // Each transfer must call balanceOfWithUpdate to update the state
    function _balanceWithRewards(address wallet) private view returns (uint256, bool, uint256) {
        _balanceState memory lState;

        (lState.resultBalance, lState.rewardCycle, lState.highReward) = 
            (_accounts[wallet].balanceBase, _accounts[wallet].lastRewardId, _accounts[wallet].isHighReward);

        if (
                (wallet == LockedMintAddress()) ||
                (wallet == AvailableMintAddress())
        ) {
            // special accounts doesn't take participation in rewards
            return (lState.resultBalance, false, 0);
        }

        lState.needUpdate = false;
        lState.rewarded = 0;

        uint32 maxRewardId = CurrentRewardCycle;
        for (; lState.rewardCycle < maxRewardId; lState.rewardCycle++) {
            lState.needUpdate = true;

            (uint96 taxed, uint24 mintIndex) = (RewardCycles[lState.rewardCycle].taxed, RewardCycles[lState.rewardCycle].mintIndex);

            uint256 historicTotalSupply = MintIndexes[mintIndex].totalSupply;
            (uint8 tire, bool tireFound) = _getIndexTireByBalance(lState.resultBalance, historicTotalSupply);

            if (tireFound) {
                uint256 tirePool = _tirePortion[tire] * taxed / 10_000;
                //TODO: Potential gas optimisation
                (uint32 regular, uint32 high) = 
                    (MintIndexes[mintIndex].tires[tire].regularLength, MintIndexes[mintIndex].tires[tire].highLength);

                uint256 rewardShare;

                unchecked {
                    uint256 nominator = 10_000;
                    uint256 denominator = 10_000 * regular + 10_100 * high;

                    if (lState.highReward) {
                        nominator *= 10_100;
                    } else {
                        nominator *= 10_000;
                    }

                    uint256 shareRatio = nominator / denominator;

                    rewardShare = tirePool * shareRatio / 10_000;

                    lState.rewarded += rewardShare;
                }
            }
        }

        return (lState.resultBalance + lState.rewarded, lState.needUpdate, lState.rewarded);
    }

    function _externalTransferCore(address from, address to, uint256 value) private returns (bool)  {
        uint256 taxRate = 0;

        if (Taxable[to] || Taxable[from])
            taxRate = Tax;

        uint256 taxValue = value * taxRate / 10_000;
        value -=  taxValue; 


        if (taxValue > 0) {
            uint256 auth1Amount = taxValue * TaxAuth1Share / 10_000;
            taxValue -= auth1Amount;
            
            if (auth1Amount > 0)
                _transferCore(from, TaxAuthoriy1, auth1Amount);

            if (taxValue > 0)
                _transferCore(from, TaxAuthoriy2, taxValue);

            RewardCycles[CurrentRewardCycle].taxed += uint96(auth1Amount);
        }

        _indexableTransferFrom(from, to, value);

        //Here RewardCycles can be be closed automaticlly
        //Just by uncommenting line below
        //newRewardCycle();

        return true;
    }
    
    function _indexableTransferFrom(address from, address to, uint256 value) private {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        _transferCore(from, to, value);

        _updateUserIndex(from, _accounts[from].balanceBase);   
        _updateUserIndex(to, _accounts[to].balanceBase);
    }


    function _newRewardCycle() private {
        uint256 nextRewardCycle = CurrentRewardCycle + 1;

        (RewardCycles[nextRewardCycle].taxed, RewardCycles[nextRewardCycle].mintIndex) = 
            (0, ActiveMintIndex);
        
        CurrentRewardCycle = uint32(nextRewardCycle);
    }

    /*################################# END - CORE LOGIC #################################*/



    function ClaimRewardWithProof(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(RewardRoots[root], "Unrecognized reward");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require (MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this reward or input is wrong");
        require (!ClaimedReward[leaf] , "You've claimed it ;-)");

        ClaimedReward[leaf] = true;
        _transferCore(TaxAuthoriy1, msg.sender, amount);
    }



    // This is one of 2 options of how launch reward cycle;
    // Another one is to do it at each transfer
    function LaunchNewRewardCycle() public onlyOwner {
        _newRewardCycle();
    }


    function SetTaxRatio(uint16 tax, uint16 share1) public onlyOwner {
        Tax = tax;
        TaxAuth1Share = share1;
    }

     function UpdateTaxAuthorities(address taxAuth1, address taxAuth2) public onlyOwner {
        address oldAuth1 = TaxAuthoriy1;
        address oldAuth2 = TaxAuthoriy2;

        TaxAuthoriy1 = taxAuth1;
        TaxAuthoriy2 = taxAuth2;

        _indexableTransferFrom(oldAuth1, taxAuth1, balanceOf(oldAuth1));
        _indexableTransferFrom(oldAuth2, taxAuth2, balanceOf(oldAuth2));
    }

    function UpdateWhitelisting(address add, bool taxStatus) public onlyOwner {
        Taxable[add] = taxStatus;
    }


    function EnableReward(bytes32 root) public onlyOwner {
        RewardRoots[root] = true;
    }

    function DisableReward(bytes32 root) public onlyOwner {
        RewardRoots[root] = false;
    }


    function DistributeReward(address[] calldata addresses, uint256[] calldata amounts, uint256 gasLimit) public onlyOwner returns(uint256) {

        address taxAuth1 = TaxAuthoriy1;

        for (uint256 i = 0; i < addresses.length; i++) {
            _transferCore(taxAuth1, addresses[i], amounts[i]);

            if (gasleft() < gasLimit)
                return i;
        }

        return addresses.length;
    }

    function BoostWallet(address wallet) public onlyOwner {
        _accounts[wallet].isHighReward = true;

        AccountTireIndex storage mainIndexTireIdx = _getAccountTireMainIndex(wallet);

        uint256 currentMintIndex = ActiveMintIndex;
        if (mainIndexTireIdx.tireIdInvert != 0) {
            IndexTire storage tireRec = MintIndexes[currentMintIndex].tires[~mainIndexTireIdx.tireIdInvert];

            (tireRec.regularLength, tireRec.highLength) = 
                (tireRec.regularLength - 1, tireRec.highLength + 1);
        }

        AccountTireIndex storage shadowIndexTireIdx = _getAccountTireShadowIndex(wallet);
        if (
            (shadowIndexTireIdx.indexId == (currentMintIndex + 1)) &&
            (shadowIndexTireIdx.tireIdInvert != 0)
        ) {
            IndexTire storage tireRec = MintIndexes[currentMintIndex + 1].tires[~shadowIndexTireIdx.tireIdInvert];

            (tireRec.regularLength, tireRec.highLength) = 
                (tireRec.regularLength - 1, tireRec.highLength + 1);
        }
    }
}