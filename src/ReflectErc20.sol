// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";

import "./ReflectDataModel.sol";
import {RewardHolderProxy} from "./RewardHolderProxy.sol";


abstract contract Reflect is Ownable2Step, IERC20, IERC20Metadata, IERC20Errors {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor (address teamWallet, uint256 tSupply, uint256 airdropSupply)
        Ownable(msg.sender)  {
        
        require(_regularTax() <= BASE_POINT, "regular tax cannot be more then 100%");
        require(_highTax() <= BASE_POINT, "high tax cannot be more then 100%");
        require(_highTax() >= _regularTax(), "high tax must be greater then or equal to regular tax");
        require(airdropSupply <= tSupply, "Airdrop supply shall be less or equal to total supply");

        TeamWallet = teamWallet;
           
        (_tierThresholds[0], _tierThresholds[1], _tierThresholds[2], _tierThresholds[3])=
            (1_0000, 7000, 3000, 900);

        (_tierThresholds[4], _tierThresholds[5], _tierThresholds[6], _tierThresholds[7]) =
            (600, 300, 90, 50);
                
        (_tierPortion[0], _tierPortion[1], _tierPortion[2], _tierPortion[3]) =
            (30_00, 23_00, 15_00, 11_00);

        (_tierPortion[4], _tierPortion[5], _tierPortion[6], _tierPortion[7]) = 
            (8_00, 6_00, 4_50, 2_50);

        _totalSupply = tSupply;
        AirdropSupply = airdropSupply;
     
        _approve(address(this), msg.sender, type(uint256).max);

        RewardHolderProxyAddress = new RewardHolderProxy();

        _initialized = true;
    }

    uint256                             constant                TIER_THRESHOLD_BASE = 100_0000;
    uint256                             constant                BASE_POINT = 100_00;
    uint256                             constant                BASE_POINT_TENS = 100_000;

    // 8 + 160 = 168 bits
    //
    bool                                public                  DexReflectIsToken1;
    IUniswapV2Pair                      public                  DEX;

    //160 bits
    address                             public                  TeamWallet;

    uint256                             public                  RegularTaxBlockInv;


    bool                                immutable internal      _initialized;
    uint256                             immutable private       _totalSupply;
    uint256                             immutable public        AirdropSupply;
    uint256                             public                  Airdropped;
    bytes32                             public                  AirdropRoot;
    RewardHolderProxy                   immutable public        RewardHolderProxyAddress;
    uint24[FEE_TIERS]                   internal                _tierThresholds;
    uint16[FEE_TIERS]                   internal                _tierPortion;
    
    uint256                             public                  Boosted;

    RewardCycle                         public                  RewardCycleData;

    mapping(address => AccountState)    internal                _accounts;

    mapping (address => bool)           public                  Taxable;
    mapping (bytes32 => bool)           public                  RewardRoots;
    mapping (bytes32 => bool)           public                  ClaimedReward;
    mapping (bytes32 => bool)           public                  ClaimedAirdrop;
    
    mapping(address account => mapping(address spender => uint256)) internal _allowances;

    /********************************** DEPENDENCY INJECTIONS **********************************/
        function _wethErc20() internal virtual view returns(IERC20);
        function _uniV2Factory() internal virtual view returns(IUniswapV2Factory);
        function _regularTax() internal virtual view returns(uint256);
        function _highTax() internal virtual view returns(uint256);

    /*################################# END - DEPENDENCY INJECTIONS #################################*/


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
                return _accounts[account].balance;
            }


            function approve(address spender, uint256 value) public virtual returns (bool) {
                _approve(msg.sender, spender, value);
                return true;
            }

            
            function transfer(address to, uint256 value) public override returns (bool) {
                return _taxableTransferCore(msg.sender, to, value);
            }

            function transferFrom(address from, address to, uint256 value) public override returns (bool)  {
                _spendAllowance(from, msg.sender, value);

                return _taxableTransferCore(from, to, value);
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
        // internal (core) version of transfer
        function _transferCore(address from, address to, uint256 value) internal {
            //cache for gas saving
            uint256 tSupply = _totalSupply;

            if (from != address(0)) {
                uint256 fromBalance = _accounts[from].balance;

                if (fromBalance < value) {
                    revert ERC20InsufficientBalance(from, fromBalance, value);
                }
                uint256 newBalance;
                unchecked {
                    // Overflow not possible: value <= fromBalance <= totalSupply.
                    newBalance = fromBalance - value;
                    //updating balance and reward cycle
                    _accounts[from].balance = newBalance;
                }

                //afterwards we need to refresh user stats
                _updateWalletStat(from, fromBalance, newBalance, tSupply);
            }

            if (to == address(0)) {
                require(false, "Burning token isn't possible");
            } else {
                uint256 newBalance;
                uint256 initBalance;

                initBalance = _accounts[to].balance;
                unchecked {
                    // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                    newBalance = value + initBalance;
                    _accounts[to].balance = newBalance;
                }
                                
                //afterwards we need to refresh user stats
                _updateWalletStat(to, initBalance, newBalance, tSupply);
            }

            emit Transfer(from, to, value);
        }

        function _updateWalletStat(address wallet, uint256 initBalance, uint256 newBalance, uint256 tSupply) internal {
            (bool userBoosted, bool userExcluded) = (_accounts[wallet].isHighReward, _accounts[wallet].excludedFromRewards);

            if ((wallet == address(this)) || userExcluded)
                return;

            (uint8 initialTier, bool initTierFound) = _getIndexTierByBalance(initBalance, tSupply);
            (uint8 newTier, bool newTierFound) = _getIndexTierByBalance(newBalance, tSupply);

            // if came up/down from rewards tires
            // or
            // change in tiers
            if ((initTierFound != newTierFound) || (initTierFound && newTierFound && (initialTier != newTier))) {
                if (initTierFound) {
                    if (userBoosted) {
                        RewardCycleData.stat[initialTier].boostedUsers.remove(wallet);
                    
                    } else {
                        RewardCycleData.stat[initialTier].regularUsers.remove(wallet);
                    }
                }

                if (newTierFound) {
                    if (userBoosted) {
                        RewardCycleData.stat[newTier].boostedUsers.add(wallet);
                    
                    } else {
                        RewardCycleData.stat[newTier].regularUsers.add(wallet);
                    }
                }
            }
        }
        

            
        function _getIndexTierByBalance(uint256 balance, uint256 tSupply) private view returns (uint8, bool) {
            unchecked {
                uint256 share = balance * TIER_THRESHOLD_BASE / tSupply;

                // using binary tree checks to lower & stable gas for all tires
                // it takes 3-4 checks to make a decision

                /*
                * t_i- _tierThresholds[i]
                * b - balance
                *                                                  t_3
                *                                                  | |
                *                               +------------------+ +---------------+
                *                              /                                      \
                *                             /                                        \
                *                    b < t_3 /                                          \ b >= t_3
                *                           /                                            \
                *                          /                                              \
                *                        t_6                                               t_1
                *                       /   \                                             /   \
                *                      /     \                                           /     \
                *                     /       \                                         /       \
                *                    /         \                                       /         \
                *           b < t_6 /           \ b >= t_6                    b < t_1 /           \ b >= t_1
                *                  /             \                                   /             \
                *                 /               \                                 /               \
                *                /                 \                               /                 \
                *               /                   \                             /                   \
                *              /                     \                           /                     \
                *            t_7                      t_4                      t_2                      t_0
                *           /   \                    /   \                    /   \                    /   \
                * b < t_7  /     \ b >= t_7 b < t_4 /     \ b >= t_4 b < t_2 /     \ b >= t_2 b < t_0 /     \ b >= t_0
                *         /       \                /       \                /       \                /       \
                *        NF        7             t_5        4              3         2              1         0
                *                               /   \
                *                      b < t_5 /     \ b >= 5
                *                             /       \
                *                            6         5
                **/

                if (share < _tierThresholds[3]) {
                    if (share < _tierThresholds[6]) {
                        if (share < _tierThresholds[7])
                            return (type(uint8).max, false);
                        else
                            return (7, true);
                    } else {
                        if (share < _tierThresholds[4]) {
                            if (share < _tierThresholds[5])
                                return (6, true);
                            else
                                return (5, true);
                        } else
                            return (4, true);
                    }
                } else {
                    if (share < _tierThresholds[1]) {
                        if (share < _tierThresholds[2])
                            return (3, true);
                        else
                            return (2, true);
                    } else {
                        if (share < _tierThresholds[0]) 
                            return (1, true);
                        else
                            return (0, true);
                    }
                }
            }

            /*
            //this is old unoptimised version:
            unchecked {
                for (uint256 j = 0; j < FEE_TIERS; ++j) {
                    if (share >= _tierThresholds[j]) {
                        return (uint8(j), true);
                    }
                }
            }

            return (type(uint8).max, false);
            //*/
        }

        // perfroms a trtoken transfer with taxation
        function _taxableTransferCore(address from, address to, uint256 value) private returns (bool) {
            uint256 taxRate = 0;

            // Do taxing only on whitelisted wallets
            if (Taxable[to] || Taxable[from])
                if (block.number >= ~RegularTaxBlockInv)
                    taxRate = _regularTax();
                else
                    taxRate = _highTax();

            //calculating total amount of taxation
            uint256 taxValue;

            //overflow must never happen
            //taxRate <= BASE_POINT
            unchecked {
                taxValue = value * taxRate / BASE_POINT;
                value -=  taxValue; 
            }

            if (taxValue > 0) 
                _transferCore(from, address(this), taxValue);            

            //main transfer
            _transferCore(from, to, value);

            return true;
        }
    /*################################# END - CORE LOGIC #################################*/


    /********************************** REWARD ALT LOGIC **********************************/
        // manual reward distro (opt1), in emg cases
        function ClaimRewardWithProof(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
            require(RewardRoots[root], "Unrecognized reward");

            bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

            require (MerkleProof.verifyCalldata(proof, root, leaf), "you're not part of this reward or input is wrong");
            require (!ClaimedReward[leaf] , "You've claimed it ;-)");

            ClaimedReward[leaf] = true;
            _wethErc20().transfer(msg.sender, amount);
        }

        // manual reward distro (opt2), in emg cases
        function DistributeReward(address[] calldata addresses, uint256[] calldata amounts, uint256 gasLimit) public onlyOwner returns(uint256) {
            for (uint256 i = 0; i < addresses.length; ++i) {
                _wethErc20().transfer(addresses[i], amounts[i]);

                if (gasleft() < gasLimit)
                    return i;
            }

            return addresses.length;
        }
        
        function EnableReward(bytes32 root) public onlyOwner {
            RewardRoots[root] = true;
        }

        function DisableReward(bytes32 root) public onlyOwner {
            RewardRoots[root] = false;
        }
    /*################################# END - REWARD ALT LOGIC #################################*/



    /********************************** AIRDROP LOGIC **********************************/
        function Airdrop(bytes32 root, bytes32[] calldata proof, uint256 amount) public {
            uint256 airdropped = Airdropped + amount;
 
            require(AirdropRoot == root, "Unrecognized airdrop");
            require(airdropped <= AirdropSupply, "Supply overflow" );
            require(amount > 0, "Amount must be non 0");

            bytes32 leaf = keccak256(abi.encode(msg.sender, amount));

            require(MerkleProof.verifyCalldata(proof, root, leaf), "You're not part of this airdrop or input is wrong");
            require(!ClaimedAirdrop[leaf], "Already claimed");

            Airdropped = airdropped;
            ClaimedAirdrop[leaf] = true;
            _mint(msg.sender, amount);
        }

        function SetAirdropRoot(bytes32 root) public onlyOwner {
            AirdropRoot = root;
        }
    /*################################# END - AIRDROP  LOGIC #################################*/

    /********************************** PRIVATE FUNCS **********************************/
        function _uni2GetAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
            require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
            require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
            uint256 amountInWithFee = amountIn * 997;
            uint256 numerator = amountInWithFee * reserveOut;
            uint256 denominator = reserveIn * 1000 + amountInWithFee;
            unchecked { //as it was in Solidity 0.5.0
                amountOut = numerator / denominator;
            }
        }

        function _transferOwnership(address newOwner) internal virtual override {
            address oldOwner = owner();

            super._transferOwnership(newOwner);

            if (_initialized) {
                _approve(address(this), oldOwner, 0);
                _approve(address(this), newOwner, type(uint256).max);

                IUniswapV2Pair dex = DEX;

                if (address(dex) != address(0)) {
                    dex.approve(oldOwner, 0);
                    dex.approve(newOwner, type(uint256).max);
                }
            }
        }
    /*################################# END - PRIVATE FUNCS #################################*/


    function GetRewardCycleTierStat(uint256 tier) public view returns(uint256, uint256) {
        return (
            RewardCycleData.stat[tier].regularUsers.length(), 
            RewardCycleData.stat[tier].boostedUsers.length()
        );
    }

    function GetRewardCycleMembersAtTier(uint256 tier, bool boosted) public view returns (address[] memory) {
        uint256 recordsLen;

        if (boosted)
            recordsLen = RewardCycleData.stat[tier].boostedUsers.length();
        else
            recordsLen = RewardCycleData.stat[tier].regularUsers.length();

        return GetRewardCycleMembersAtTier(tier, boosted, recordsLen, 0);
    }

    function GetRewardCycleMembersAtTier(uint256 tier, bool boosted, uint256 pageSize, uint256 page) public view returns (address[] memory) {
        uint256 recordsLen;

        if (boosted)
            recordsLen = RewardCycleData.stat[tier].boostedUsers.length();
        else
            recordsLen = RewardCycleData.stat[tier].regularUsers.length();

        uint256 indexStart = pageSize * page; //inclusive
        uint256 indexEnd = indexStart + page; //non-inlusive
        if (indexStart >= recordsLen)
            return new address[](0);
        
        if  (indexEnd > recordsLen)
            indexEnd = recordsLen;

        address[] memory result = new address[](indexEnd - indexStart);

        for (uint256 i = 0; i < result.length; i++)
            if (boosted)
                result[i] = RewardCycleData.stat[tier].boostedUsers.at(i + indexStart);
            else
                result[i] = RewardCycleData.stat[tier].regularUsers.at(i + indexStart);

        return result;
    }

    function GetWalletRewardTier(address wallet) public view returns (uint256, bool, bool) {
        for (uint256 tire = 0; tire < FEE_TIERS; tire++) {
            if (RewardCycleData.stat[tire].regularUsers.contains(wallet))
                return (tire, false, true);
                
            if (RewardCycleData.stat[tire].boostedUsers.contains(wallet))
                return (tire, true, true);
        }

        return (type(uint256).max, false, false);
    }

    function RegularTaxBlock() public view returns (uint256) {
        return ~RegularTaxBlockInv;
    }

    // creating pool and adding liq
    function LaunchUniV2Pool(uint256 lowTaxInBlocks) public onlyOwner returns(address) {
        require(address(DEX) == address(0), "DEX already initialised");
        require(AirdropSupply < _totalSupply, "0 supply for the pool");

        IUniswapV2Pair pair = IUniswapV2Pair(_uniV2Factory().createPair(address(_wethErc20()), address(this)));
        
        _accounts[address(pair)].excludedFromRewards = true;

        //We can have total supply only once, so second time it must crash
        _mint(address(pair), _totalSupply - AirdropSupply);
        _wethErc20().transfer(address(pair), _wethErc20().balanceOf(address(this)));

        pair.mint(address(this));
        pair.approve(msg.sender, type(uint256).max);

        Taxable[address(pair)] = true;
        DEX = pair;
        DexReflectIsToken1 = pair.token0() == address(_wethErc20());

        RegularTaxBlockInv = ~(block.number + lowTaxInBlocks);

        return address(pair);
    }

    function LaunchNewRewardCycle(uint256 priceLimitNE28, bool skipSwap, uint256 rewardDistroShare) public onlyOwner {
        if (!skipSwap)
            FixEthRewards(priceLimitNE28);

        require(rewardDistroShare <= BASE_POINT, "rewardDistroShare cannot exceed 100%");

        uint256 taxed = RewardCycleData.taxedEth * rewardDistroShare / BASE_POINT;
        RewardCycleData.taxedEth = 0;

        for (uint256 i = 0; i < FEE_TIERS; ++i) {
            RewardCycleStat storage rewStat = RewardCycleData.stat[i];

            uint256 tierPool = _tierPortion[i] * taxed / BASE_POINT;
            uint256 bstLen = rewStat.boostedUsers.length();
            uint256 regLen = rewStat.regularUsers.length();
            uint256 shareRatio;
            uint256 reward;

            if (regLen + bstLen == 0)
                continue;

            unchecked {
                /*
                //uint256 nominator = (100 - boosted) * BASE_POINT_TENS; //(using 2's complaint we can get)
                                                                    //(101 + ~boosted) * BASE_POINT_TENS
                uint256 denominator = 100 * (regular + boosted);
                uint256 shareRatio = nominator / denominator;
                //*/
                shareRatio = ((101 + ~bstLen) * BASE_POINT_TENS) / ( (regLen + bstLen) * 100);
                reward = shareRatio * tierPool / BASE_POINT_TENS;
            }



            for (uint256 j = 0; j < regLen; j++) {
                address rewardWallet = rewStat.regularUsers.at(j);

                unchecked {
                    _wethErc20().transfer(rewardWallet, reward);
                }
            }

            unchecked {
                shareRatio += 1_000; //+ 1%
                reward = shareRatio * tierPool / BASE_POINT_TENS;
            }

            if (reward == 0)
                continue;


            for (uint256 j = 0; j < bstLen; j++) {
                address rewardWallet = rewStat.boostedUsers.at(j);

                unchecked {
                    _wethErc20().transfer(rewardWallet, reward);
                }
            }
        }
    }

    function FixEthRewards(uint256 priceLimitNE28) public onlyOwner {
        (IUniswapV2Pair pair, bool isInToken1) = 
            (DEX, DexReflectIsToken1);

        uint256 sellAmount = _accounts[address(this)].balance;
        uint256 amountOut0 = 0;
        uint256 amountOut1 = 0;

        require (sellAmount > 0, "Empty balance");

        {
            uint256 expectedOut = sellAmount * priceLimitNE28 / 1e28; //close to Q96
            (uint112 reserveIn, uint112 reserveOut, ) = pair.getReserves();

            if (isInToken1)
                (reserveIn, reserveOut) = (reserveOut, reserveIn) ;

            if (isInToken1)
                amountOut0 = _uni2GetAmountOut(sellAmount, reserveIn, reserveOut);
            else
                amountOut1 = _uni2GetAmountOut(sellAmount, reserveIn, reserveOut);

            require((amountOut0 | amountOut1) >= expectedOut, "Price slippage too small");
        }

        RewardHolderProxy holder = RewardHolderProxyAddress;

        //sending without taxes
        _transferCore(address(this), address(pair), sellAmount);
        pair.swap(amountOut0, amountOut1, address(holder), new bytes(0));

        unchecked {
            uint256 totalTaxed = amountOut0 | amountOut1;
            uint256 rewAmount = totalTaxed / 2;

            holder.SendTokenBack(_wethErc20(), totalTaxed);

            //uint96 is quite big for eth
            //uint32 is ok up to 19 January 2038, at 03:14:07 UTC
            //overflow is ok
            (RewardCycleData.taxedEth, RewardCycleData.lastConvertedTime) = 
                (uint96(RewardCycleData.taxedEth + rewAmount), uint32(block.timestamp));

            _wethErc20().transfer(TeamWallet, totalTaxed - rewAmount);
        }
    }


    function UpdateTeamWallet(address teamWallet) public onlyOwner {
        TeamWallet = teamWallet;
    }

    function UpdateWhitelisting(address add, bool taxStatus) public onlyOwner {
        Taxable[add] = taxStatus;
    }



    function BoostWallet(address wallet) public onlyOwner {
        require(!_accounts[wallet].isHighReward, "Account could be boosted only once");
        require(Boosted < 10, "No more then 10 users could be boosted");
        ++Boosted;

        _accounts[wallet].isHighReward = true;


        (uint8 tier, bool tierFound) = _getIndexTierByBalance(_accounts[wallet].balance, _totalSupply);

        if (tierFound) {
            RewardCycleStat storage rewstat = RewardCycleData.stat[tier];

            rewstat.regularUsers.remove(wallet);
            rewstat.boostedUsers.add(wallet);
        }
    }

    function ExcludeWalletFromRewards(address wallet) public onlyOwner {
        uint256 balance = _accounts[wallet].balance;

        if (!_accounts[wallet].excludedFromRewards) {
            _accounts[wallet].excludedFromRewards = true;

            
            (uint8 tier, bool tierFound) = _getIndexTierByBalance(balance, _totalSupply);
            if (tierFound) {
                if (_accounts[wallet].isHighReward) {
                    RewardCycleData.stat[tier].boostedUsers.remove(wallet);
                
                } else {
                    RewardCycleData.stat[tier].regularUsers.remove(wallet);
                }
            }
        }
    }
}