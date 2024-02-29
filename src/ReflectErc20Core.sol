// SPDX-License-Identifier: NONE
pragma solidity ^0.8.19;


import "./ReflectDataModel.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";


abstract contract ReflectErc20Core is Ownable2Step, IERC20, IERC20Metadata, IERC20Errors {
    uint256                             constant                TIRE_THRESHOLD_BASE = 1_000_000;


    uint24                              public                  ActiveMintIndex;
    uint8                               internal                _lastShadowIndexedTireInvert;
    uint16                              internal                _lastShadowIndexedChunkInvert;
    uint32                              public                  CurrentRewardCycle;



    uint16                              public                  Tax;
    uint16                              public                  TaxAuth1Share;
    bool                                public                  AutoTaxDistributionEnabled;

    address                             public                  TaxAuthoriy1;
    address                             public                  TaxAuthoriy2;
    bytes32                             internal                _nextAirdropRoot;
    uint256                             internal                _nextAirdrop;
    uint24[FEE_TIRES]                   internal                _tireThresholds;
    uint16[FEE_TIRES]                   internal                _tirePortion;

    mapping(address => AccountState)    internal                _accounts;
    mapping(uint256 => MintIndex)       public                  MintIndexes;
    mapping(uint256 => RewardCycle)     public                  RewardCycles;

    mapping (address => bool)           public                  Taxable;
    mapping (bytes32 => uint256)        public                  AirdropWaveRoots;
    mapping (bytes32 => bool)           public                  RegistredAirdrop;
    mapping (bytes32 => bool)           public                  ClaimedAirdrop;
    mapping (bytes32 => bool)           public                  RewardRoots;
    mapping (bytes32 => bool)           public                  ClaimedReward;
    
    //mapping(address account => uint256) internal                _balances;
    mapping(address account => mapping(address spender => uint256)) internal _allowances;





    function _shadowMintIndexEnabled() internal virtual view returns (bool);
    function balanceOf(address account) public virtual view returns (uint256);
    function balanceOfWithUpdate(address account) public virtual returns (uint256);


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
        return MintIndexes[ActiveMintIndex].totalSupply;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function LockedMintAddress() public pure returns (address) {
        return address(uint160(0xdeadc1c0220001));
    }
    function AvailableMintAddress() public pure returns (address) {
        return address(uint160(0xdeadc1c0220002));
    }

    
    function LastShadowIndexedTire() public view returns(uint8) {
        return ~_lastShadowIndexedTireInvert;
    }

    function LastShadowIndexedChunk() public view returns(uint16) {
        return ~_lastShadowIndexedChunkInvert;
    }

    function GetTireData(uint256 mint, uint256 tire) public view returns(uint32, uint32, uint32) {
        IndexTire storage tireRecord = MintIndexes[mint].tires[tire];

        return (tireRecord.regularLength, tireRecord.highLength, tireRecord.chunksCount);
    }

    function GetTireChunk(uint256 mint, uint256 tire, uint256 chunk) public view returns(uint8, address[CHUNK_SIZE] memory) {
        IndexChunk storage chunkRec = MintIndexes[mint].tires[tire].chunks[chunk];

        return (chunkRec.length, chunkRec.list);
    }

    
    function approve(address spender, uint256 value) public virtual returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

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
    /*
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }//*/

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
            uint256 lockedForMint = _accounts[LockedMintAddress()].balanceBase;

            if (lockedForMint < value) {
                //Must never happen
                require(false, "Not enough tokens available to do mint");
            }

            _accounts[LockedMintAddress()].balanceBase = lockedForMint - value;
        } else {
            uint256 fromBalance = balanceOfWithUpdate(from);
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _accounts[from].balanceBase = fromBalance - value;
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
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _accounts[to].balanceBase += value;
            }
        }

        emit Transfer(from, to, value);
    }
}