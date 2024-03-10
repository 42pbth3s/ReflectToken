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
    constructor (uint16 tax, uint16 rewardShare, address teamWallet, uint256 tSupply)
        Ownable(msg.sender)  {
        
        require(tax <= 10_000, "tax cannot be more then 100%");
        require(rewardShare <= 10_000, "reward share cannot be more then 100%");

        Tax = tax;
        RewardShare = rewardShare;
        TeamWallet = teamWallet;

        AutoTaxDistributionEnabled = true;
           
        (_tierThresholds[0], _tierThresholds[1], _tierThresholds[2], _tierThresholds[3])=
            (1_0000, 7000, 3000, 900);

        (_tierThresholds[4], _tierThresholds[5], _tierThresholds[6], _tierThresholds[7]) =
            (600, 300, 90, 50);
        
        
        (_tierPortion[0], _tierPortion[1], _tierPortion[2], _tierPortion[3]) =
            (30_00, 23_00, 15_00, 11_00);

        (_tierPortion[4], _tierPortion[5], _tierPortion[6], _tierPortion[7]) = 
            (8_00, 6_00, 4_50, 2_50);

        _totalSupply = tSupply;

        _mint(address(this), tSupply);
        _approve(address(this), msg.sender, type(uint256).max);

        _initialized = true;
    }

    uint256                             constant                TIER_THRESHOLD_BASE = 1_000_000;


    uint32                              public                  CurrentRewardCycle;

    uint16                              public                  Tax;
    uint16                              public                  RewardShare;
    bool                                public                  AutoTaxDistributionEnabled;
    bool                                immutable internal      _initialized;

    address                             public                  TeamWallet;
    uint256                             immutable private       _totalSupply;
    uint24[FEE_TIERS]                   internal                _tierThresholds;
    uint16[FEE_TIERS]                   internal                _tierPortion;
    
    uint256                             public                  Boosted;

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
            _accounts[account].lastRewardId = CurrentRewardCycle;
            if (rewarded != 0)
                _transferCore(address(this), account, rewarded, true);
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
        _transferCore(from, to, value, false);
    }

    function _transferCore(address from, address to, uint256 value, bool disableToRewards) internal {
        uint256 tSupply = _totalSupply;
        uint32 currewCycle = CurrentRewardCycle;

        if (from == address(0)) {
            require(!_initialized, "Can only mint at the creation time");
        } else {
            (uint256 fromBalance, , ) = _balanceWithRewards(from);

            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            uint256 newBalance;
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                newBalance = fromBalance - value;
                (_accounts[from].balanceBase, _accounts[from].lastRewardId) 
                    = (newBalance, currewCycle);
            }

            _updateWalletStat(from, fromBalance, newBalance, tSupply);
        }

        if (to == address(0)) {
            require(false, "Burning token isn't possible");
        } else {            
            uint256 initBalance = _accounts[to].balanceBase;
            uint256 newBalance;

            if (disableToRewards)
                (initBalance, , ) = _balanceWithRewards(to);
            else 
                initBalance = _accounts[to].balanceBase;

            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                newBalance = initBalance + value;
                _accounts[to].balanceBase = newBalance;
            }
            
            _updateWalletStat(to, initBalance, newBalance, tSupply);
        }

        emit Transfer(from, to, value);
    }

    function _updateWalletStat(address wallet, uint256 initBalance, uint256 newBalance, uint256 tSupply) private {
        (uint8 initialTier, bool initTierFound) = _getIndexTierByBalance(initBalance, tSupply);
        (uint8 newTier, bool newTierFound) = _getIndexTierByBalance(newBalance, tSupply);
        (bool userBoosted, bool userExcluded) = (_accounts[wallet].isHighReward, _accounts[wallet].excludedFromRewards);

        if ((wallet == address(this)) || userExcluded)
            return;


        if ((initTierFound != newTierFound) || (initTierFound && newTierFound && (initialTier != newTier))) {
            if (initTierFound) {
                if (userBoosted) {
                    --RewardCycles[CurrentRewardCycle].stat[initialTier].boostedMembers;
                
                } else {
                    --RewardCycles[CurrentRewardCycle].stat[initialTier].regularMembers;
                }
            }

            if (newTierFound) {
                if (userBoosted) {
                    ++RewardCycles[CurrentRewardCycle].stat[newTier].boostedMembers;
                
                } else {
                    ++RewardCycles[CurrentRewardCycle].stat[newTier].regularMembers;
                }
            }
        }
    }
    

        
    function _getIndexTierByBalance(uint256 balance, uint256 tSupply) private view returns (uint8, bool) {        
        uint256 share = balance * TIER_THRESHOLD_BASE / tSupply;

        unchecked {
            for (uint256 j = 0; j < FEE_TIERS; ++j) {
                if (share >= _tierThresholds[j]) {
                    return (uint8(j), true);
                }
            }
        }

        return (type(uint8).max, false);
    }

    function _balanceWithRewards(address wallet) private view returns (uint256, bool, uint256) {
        uint32 maxRewardId = CurrentRewardCycle;

        return _balanceWithRewardsToRewardCycle(wallet, maxRewardId);
    }

    struct _balanceState {
        uint256 resultBalance;
        bool needUpdate;
        uint256 rewarded;
        uint256 rewardCycle;
        bool highReward;
        uint32 maxRewardId;
        uint8 tier;
    }

    //This funcation assumes that balance hasn't been changed since last transfer happen
    // Each transfer must call balanceOfWithUpdate to update the state
    function _balanceWithRewardsToRewardCycle(address wallet, uint32 maxRewardId) private view returns (uint256, bool, uint256) {
        _balanceState memory lState;

        AccountState storage accState = _accounts[wallet];

        {
            bool excluded;
            (lState.resultBalance, lState.rewardCycle, lState.highReward, excluded) = 
                (accState.balanceBase, accState.lastRewardId, accState.isHighReward, accState.excludedFromRewards);

            if ((address(this) == wallet) || excluded)
                return (lState.resultBalance, false, 0);
        }

        lState.needUpdate = false;
        lState.rewarded = 0;
        lState.maxRewardId = maxRewardId;

        {
            bool tierFound;
            (lState.tier, tierFound) = _getIndexTierByBalance(lState.resultBalance, _totalSupply);

            //No rewards with given balance
            //just return balance as it is and update based on lastRewardId
            //that avoids pointless looping through all cycles and wasting gas

            if (!tierFound)
                return (lState.resultBalance, lState.rewardCycle < lState.maxRewardId, 0);
        }

        for (; lState.rewardCycle < lState.maxRewardId; ++lState.rewardCycle) {
            lState.needUpdate = true;

            RewardCycle storage rewCycle = RewardCycles[lState.rewardCycle];

            unchecked {
                uint96 taxed = rewCycle.taxed;
                    
                uint256 tierPool = _tierPortion[lState.tier] * taxed / 100_00;
                (uint32 regular, uint32 boosted) = 
                    (rewCycle.stat[lState.tier].regularMembers, rewCycle.stat[lState.tier].boostedMembers);
                uint256 nominator = (100 - boosted) * 100_000;
                uint256 denominator = 100 * (regular + boosted);
                uint256 shareRatio = nominator / denominator;

                if (lState.highReward) {
                    shareRatio += 1_000;
                } 

                uint256 rewardShare = tierPool * shareRatio / 100_000;

                lState.rewarded += rewardShare;
            }
        }

        unchecked {
            return (lState.resultBalance + lState.rewarded, lState.needUpdate, lState.rewarded);
        }
    }

    function _externalTransferCore(address from, address to, uint256 value) private returns (bool)  {
        uint256 taxRate = 0;

        if (Taxable[to] || Taxable[from])
            taxRate = Tax;

        uint256 taxValue;

        //overflow must never happen
        unchecked {
            taxValue = value * taxRate / 10_000;
            value -=  taxValue; 
        }


        if (taxValue > 0) {
            uint256 rewAmount = taxValue * RewardShare / 10_000;
            taxValue -= rewAmount;
            
            if (rewAmount > 0)
                _transferCore(from, address(this), rewAmount);

            if (taxValue > 0)
                _transferCore(from, TeamWallet, taxValue);

            if (AutoTaxDistributionEnabled)
                RewardCycles[CurrentRewardCycle].taxed += uint96(rewAmount);
        }

        _transferCore(from, to, value);

        //Here RewardCycles can be be closed automaticlly
        //Just by uncommenting line below
        //newRewardCycle();

        return true;
    }

    function _newRewardCycle() private {
        uint256 oldRewardCycle = CurrentRewardCycle;
        uint256 nextRewardCycle;
        unchecked {
            nextRewardCycle = CurrentRewardCycle + 1;            
        }

        RewardCycles[nextRewardCycle].taxed = 0;
        
        CurrentRewardCycle = uint32(nextRewardCycle);


        for (uint256 i = 0; i < FEE_TIERS; ++i) {
            (
                RewardCycles[nextRewardCycle].stat[i].regularMembers, 
                RewardCycles[nextRewardCycle].stat[i].boostedMembers
            ) = 
                (
                    RewardCycles[oldRewardCycle].stat[i].regularMembers, 
                    RewardCycles[oldRewardCycle].stat[i].boostedMembers
                );
        }
    }

    /*################################# END - CORE LOGIC #################################*/



    function ClaimRewardWithProof(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
        require(RewardRoots[root], "Unrecognized reward");

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

        require (MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this reward or input is wrong");
        require (!ClaimedReward[leaf] , "You've claimed it ;-)");

        ClaimedReward[leaf] = true;
        _transferCore(address(this), msg.sender, amount);
    }



    // This is one of 2 options of how launch reward cycle;
    // Another one is to do it at each transfer
    function LaunchNewRewardCycle() public onlyOwner {
        _newRewardCycle();
    }


    function SetTaxRatio(uint16 tax, uint16 rewardShare) public onlyOwner {
        require(tax <= 10_000, "tax cannot be more then 100%");
        require(rewardShare <= 10_000, "reward share cannot be more then 100%");
        Tax = tax;
        RewardShare = rewardShare;
    }

    function UpdateTeamWallet(address teamWallet) public onlyOwner {
        address oldTeamWallet = TeamWallet;

        TeamWallet = teamWallet;

        _transferCore(oldTeamWallet, teamWallet, balanceOf(oldTeamWallet));
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
        for (uint256 i = 0; i < addresses.length; ++i) {
            _transferCore(address(this), addresses[i], amounts[i]);

            if (gasleft() < gasLimit)
                return i;
        }

        return addresses.length;
    }

    function BoostWallet(address wallet) public onlyOwner {
        require(!_accounts[wallet].isHighReward, "Account could be boosted only once");
        require(Boosted < 10, "No more then 10 users could be boosted");
        ++Boosted;

        _accounts[wallet].isHighReward = true;


        (uint8 tier, bool tierFound) = _getIndexTierByBalance(_accounts[wallet].balanceBase, _totalSupply);

        if (tierFound) {
            RewardCycleStat storage rewstat = RewardCycles[CurrentRewardCycle].stat[tier];

            (rewstat.regularMembers, rewstat.boostedMembers) = (rewstat.regularMembers - 1, rewstat.boostedMembers + 1);
        }
    }

    function SwicthAutoTaxDistribution(bool newStatus) public onlyOwner {
        AutoTaxDistributionEnabled = newStatus;
    }

    function ExcludeWalletFromRewards(address wallet) public onlyOwner {
        uint256 balance = balanceOfWithUpdate(wallet);

        if (!_accounts[wallet].excludedFromRewards) {
            _accounts[wallet].excludedFromRewards = true;

            
            (uint8 tier, bool tierFound) = _getIndexTierByBalance(balance, _totalSupply);

            if (tierFound) {
                if (_accounts[wallet].isHighReward) {
                    --RewardCycles[CurrentRewardCycle].stat[tier].boostedMembers;
                
                } else {
                    --RewardCycles[CurrentRewardCycle].stat[tier].regularMembers;
                }
            }
        }
    }

    //restricted to owner because it can mess up everything 
    //in cases if user moving reward tier up
    function ProcessRewardsForUser(address account, uint32 maxRewardId) public onlyOwner {
        require(maxRewardId <= CurrentRewardCycle, "maxRewardId cannot exceed current reward cycle id");

        (, bool requireUpdate, uint256 rewarded) = _balanceWithRewardsToRewardCycle(account, maxRewardId);

        if (requireUpdate) {
            _accounts[account].lastRewardId = maxRewardId;
            if (rewarded != 0)
                _transferCore(address(this), account, rewarded, true);
        }
    }
     
}