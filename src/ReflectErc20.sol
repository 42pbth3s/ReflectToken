// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "./ReflectDataModel.sol";

contract Reflect is Ownable2Step, IERC20, IERC20Metadata, IERC20Errors {
    constructor (uint16 tax, uint16 share1, address taxAuth1, address taxAuth2, uint256 amount1, uint256 amount2, uint256 ownerAmount)
        Ownable(msg.sender)  {
        
        Tax = tax;
        TaxAuth1Share = share1;
        TaxAuthoriy1 = taxAuth1;
        TaxAuthoriy2 = taxAuth2;


        AutoTaxDistributionEnabled = true;
           
        (_tireThresholds[0], _tireThresholds[1], _tireThresholds[2], _tireThresholds[3])=
            (1_0000, 7000, 3000, 900);

        (_tireThresholds[4], _tireThresholds[5], _tireThresholds[6], _tireThresholds[7]) =
            (600, 300, 90, 50);
        
        
        (_tirePortion[0], _tirePortion[1], _tirePortion[2], _tirePortion[3]) =
            (30_00, 23_00, 15_00, 11_00);

        (_tirePortion[4], _tirePortion[5], _tirePortion[6], _tirePortion[7]) = 
            (8_00, 6_00, 4_50, 2_50);

        _totalSupply = amount1 + amount2 + ownerAmount;

        _mint(taxAuth1, amount1);
        _mint(taxAuth2, amount2);
        _mint(msg.sender, ownerAmount);
        
    }

    uint256                             constant                TIRE_THRESHOLD_BASE = 1_000_000;


    uint32                              public                  CurrentRewardCycle;



    uint16                              public                  Tax;
    uint16                              public                  TaxAuth1Share;
    bool                                public                  AutoTaxDistributionEnabled;

    address                             public                  TaxAuthoriy1;
    address                             public                  TaxAuthoriy2;
    uint256                             private                 _totalSupply;
    uint256                             internal                _totalMinted;
    uint24[FEE_TIRES]                   internal                _tireThresholds;
    uint16[FEE_TIRES]                   internal                _tirePortion;

    mapping(address => AccountState)    internal                _accounts;
    mapping(uint256 => RewardCycle)     public                  RewardCycles;

    mapping (address => bool)           public                  Taxable;
    mapping (bytes32 => bool)           public                  RewardRoots;
    mapping (bytes32 => bool)           public                  ClaimedReward;
    
    //mapping(address account => uint256) internal                _balances;
    mapping(address account => mapping(address spender => uint256)) internal _allowances;

    /********************************** GENERIC VIEW FUNCTIONs **********************************/
        function name() public pure returns (string memory) {
            return "$REFLECT";
        }
        function symbol() public pure returns (string memory) {
            return "$REFLECT";
        }

        function decimals() public pure returns (uint8) {
            return 18;
        }

        function totalSupply() public view returns (uint256) {
            return _totalSupply;
        }
        
        function allowance(address owner, address spender) public view returns (uint256) {
            return _allowances[owner][spender];
        }


    /*################################# END - GENERIC VIEW FUNCTIONS #################################*/



    /********************************** CORE LOGIC **********************************/

    function balanceOf(address account) public view returns (uint256) {
        (uint256 balance, ,) = _balanceWithRewards(account);
        return balance;
    }

    function balanceOfWithUpdate(address account) public returns (uint256) {
        (uint256 balance, bool requireUpdate, uint256 rewarded) = _balanceWithRewards(account);

        if (requireUpdate) {
            _transferCore(TaxAuthoriy1, account, rewarded);
        }

        return balance;
    }


     
    function approve(address spender, uint256 value) public virtual returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    
    function transfer(address to, uint256 value) public override returns (bool) {
        return _externalTransferCore(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool)  {
        _spendAllowance(from, msg.sender, value);

        return _externalTransferCore(from, to, value);
    }


    //++++++++++++++++++++++++++++++++ PRIVATE +++++++++++++++++++++

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _transferCore(address(0), account, value);
    }
    
    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _transferCore(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows            
            _totalMinted += value;

            require(_totalMinted <= _totalSupply, "Cannot mint more then initial supply");
        } else {
            uint256 tSupply = _totalSupply;
            (uint8 initialTire, bool tireFound) = _getIndexTireByBalance(_accounts[from].balanceBase, tSupply);

            uint256 fromBalance = balanceOfWithUpdate(from);

            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            uint256 newBalance;
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                newBalance = fromBalance - value;
                _accounts[from].balanceBase  = newBalance;
            }

            if (tireFound) {
                uint8 newTire;
                (newTire, tireFound) = _getIndexTireByBalance(newBalance, tSupply);

                bool userBoosted = _accounts[from].isHighReward;

                if (!tireFound || (initialTire != newTire)) {
                    if (userBoosted) {
                        --RewardCycles[CurrentRewardCycle].stat[initialTire].boostedMembers;

                        if (tireFound) {
                            ++RewardCycles[CurrentRewardCycle].stat[newTire].boostedMembers;
                        }
                    } else {
                        --RewardCycles[CurrentRewardCycle].stat[initialTire].regularMembers;

                        if (tireFound) {
                            ++RewardCycles[CurrentRewardCycle].stat[newTire].regularMembers;
                        }
                    }
                }
            }
        }

        if (to == address(0)) {
            require(false, "Burning token isn't possible");
            /*
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }//*/
        } else {
            uint256 tSupply = _totalSupply;
            (uint8 initialTire, bool initTireFound) = _getIndexTireByBalance(_accounts[to].balanceBase, tSupply);
            
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _accounts[to].balanceBase += value;
            }

            (uint8 newTire, bool newTireFound) = _getIndexTireByBalance(_accounts[to].balanceBase, tSupply);

            if ((initTireFound != newTireFound) || (initTireFound && newTireFound && (initialTire != newTire))) {
                bool userBoosted = _accounts[from].isHighReward;

                if (initTireFound) {
                    if (userBoosted) {
                        --RewardCycles[CurrentRewardCycle].stat[initialTire].boostedMembers;
                 
                    } else {
                        --RewardCycles[CurrentRewardCycle].stat[initialTire].regularMembers;
                    }
                }

                if (newTireFound) {
                    if (userBoosted) {
                        ++RewardCycles[CurrentRewardCycle].stat[newTire].boostedMembers;
                 
                    } else {
                        ++RewardCycles[CurrentRewardCycle].stat[newTire].regularMembers;
                    }
                }
            }
        }

        emit Transfer(from, to, value);
    }


        
    function _getIndexTireByBalance(uint256 balance, uint256 tSupply) private view returns (uint8, bool) {        
        uint256 share = balance * TIRE_THRESHOLD_BASE / tSupply;

        unchecked {
            for (uint256 j = 0; j < FEE_TIRES; j++) {
                if (share >= _tireThresholds[j]) {
                    return (uint8(j), true);
                }
            }
        }

        return (type(uint8).max, false);
    }

    struct _balanceState {
        uint256 resultBalance;
        bool needUpdate;
        uint256 rewarded;
        uint256 rewardCycle;
        bool highReward;
        uint256 totalSupply;
    }

    //This funcation assumes that balance hasn't been changed since last transfer happen
    // Each transfer must call balanceOfWithUpdate to update the state
    function _balanceWithRewards(address wallet) private view returns (uint256, bool, uint256) {
        _balanceState memory lState;

        AccountState storage accState = _accounts[wallet];

        (lState.resultBalance, lState.rewardCycle, lState.highReward) = 
            (accState.balanceBase, accState.lastRewardId, accState.isHighReward);

        lState.needUpdate = false;
        lState.rewarded = 0;
        lState.totalSupply = _totalSupply;

        uint32 maxRewardId = CurrentRewardCycle;
        for (; lState.rewardCycle < maxRewardId; lState.rewardCycle++) {
            lState.needUpdate = true;

            uint96 taxed = RewardCycles[lState.rewardCycle].taxed;
            (uint8 tire, bool tireFound) = _getIndexTireByBalance(lState.resultBalance, lState.totalSupply);

            if (tireFound) {
                uint256 tirePool = _tirePortion[tire] * taxed / 10_000;
                //TODO: Potential gas optimisation
                (uint32 regular, uint32 high) = 
                    (RewardCycles[lState.rewardCycle].stat[tire].regularMembers, RewardCycles[lState.rewardCycle].stat[tire].boostedMembers);

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

            if (AutoTaxDistributionEnabled)
                RewardCycles[CurrentRewardCycle].taxed += uint96(auth1Amount);
        }

        _transferCore(from, to, value);

        //Here RewardCycles can be be closed automaticlly
        //Just by uncommenting line below
        //newRewardCycle();

        return true;
    }

    function _newRewardCycle() private {
        uint256 nextRewardCycle = CurrentRewardCycle + 1;

        RewardCycles[nextRewardCycle].taxed = 0;
        
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

        _transferCore(oldAuth1, taxAuth1, balanceOf(oldAuth1));
        _transferCore(oldAuth2, taxAuth2, balanceOf(oldAuth2));
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
        require(!_accounts[wallet].isHighReward, "Account could be boosted only once");
        //TODO: limit max amount

        _accounts[wallet].isHighReward = true;


        (uint8 tire, bool tireFound) = _getIndexTireByBalance(_accounts[wallet].balanceBase, _totalSupply);

        if (tireFound) {
            RewardCycleStat storage rewstat = RewardCycles[CurrentRewardCycle].stat[tire];

            (rewstat.regularMembers, rewstat.boostedMembers) = (rewstat.regularMembers - 1, rewstat.boostedMembers + 1);
        }
    }

    function SwicthAutoTaxDistribution(bool newStatus) public onlyOwner{
        AutoTaxDistributionEnabled = newStatus;
    }
}