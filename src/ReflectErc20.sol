// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract Reflect is ERC20, Ownable2Step {
    

    uint16                      public                  Ratio1;
    uint16                      public                  Tax;

    address                     public                  TeamWallet;
    address                     public                  Destination2;

    mapping (address => bool)   public                  Taxable;
    mapping (bytes32 => bool)   public                  AirdropWaveRoots;
    mapping (bytes32 => bool)   public                  ClaimedAirdrop;
    mapping (bytes32 => bool)   public                  RewardRoots;
    mapping (bytes32 => bool)   public                  ClaimedReward;

    constructor (uint16 tax, uint16 r1, address teamWallet, address d2)
        ERC20("$REFLECT", "$REFLECT") 
        Ownable(msg.sender) {
        
        Tax = tax;
        Ratio1 = r1;
        TeamWallet = teamWallet;        
        Destination2 = d2;
    }


    function transfer(address to, uint256 value) public override returns (bool) {
        uint256 taxRate = 0;

        if (Taxable[to])
            taxRate = Tax;

        uint256 taxValue = value * taxRate / 10_000;
        value -=  taxValue; 

        bool result = super.transfer(to, value);

        if (taxValue > 0) {
            uint256 v1 = taxValue * Ratio1 / 10_000;
            taxValue -= v1;
            
            result = result && super.transfer(TeamWallet, v1);
            result = result && super.transfer(Destination2, taxValue);
        }

        return result;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool)  {
        uint256 taxRate = 0;

        if (Taxable[to])
            taxRate = Tax;

        uint256 taxValue = value * taxRate / 10_000;
        value -=  taxValue; 

        bool result = super.transferFrom(from, to, value);

        if (taxValue > 0) {
            uint256 v1 = taxValue * Ratio1 / 10_000;
            taxValue -= v1;
            
            result = result && super.transferFrom(from, TeamWallet, v1);
            result = result && super.transferFrom(from, Destination2, taxValue);
        }

        return result;
    }


    function Airdrop(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(AirdropWaveRoots[root], "Unrecognized airdrop");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require (MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this airdrop or input is wrong");

        ClaimedAirdrop[leaf] = true;
        _mint(msg.sender, amount);
    }

    function ClaimRewardWithProof(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(RewardRoots[root], "Unrecognized reward");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require (MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this reward or input is wrong");

        ClaimedReward[leaf] = true;
        _update(TeamWallet, msg.sender, amount);
    }





    function SetTaxRatio(uint16 tax, uint16 r1) public onlyOwner {
        Tax = tax;
        Ratio1 = r1;
    }

     function UpdateTaxDests(address d1, address d2) public onlyOwner {
        TeamWallet = d1;        
        Destination2 = d2;
    }

    function UpdateWhitelisting(address add, bool taxStatus) public onlyOwner {
        Taxable[add] = taxStatus;
    }

    function EnableAirdrop(bytes32 root) public onlyOwner {
        AirdropWaveRoots[root] = true;
    }

    function DisableAirdrop(bytes32 root) public onlyOwner {
        AirdropWaveRoots[root] = false;
    }

    function MintTo(address account, uint256 value) public onlyOwner {
        _mint(account, value);
    }

    function EnableReward(bytes32 root) public onlyOwner {
        RewardRoots[root] = true;
    }

    function DisableReward(bytes32 root) public onlyOwner {
        RewardRoots[root] = false;
    }


    function DistributeReward(address[] calldata addresses, uint256[] calldata amounts, uint256 gasLimit) public onlyOwner returns(uint256) {

        address teamWallet = TeamWallet;

        for (uint256 i = 0; i < addresses.length; i++) {
            _update(teamWallet, addresses[i], amounts[i]);

            if (gasleft() < gasLimit)
                return i;
        }

        return addresses.length;
    }
}