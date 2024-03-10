// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ReflectDebug} from "../src/ReflectErc20Debug.sol";
import "../src/ReflectDataModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


bytes16 constant HEX_DIGITS = "0123456789abcdef";

contract CounterTest is Test {


    
    ReflectDebug                            public              TokenContract;

    address                                 public              RewardWallet;
    address                                 public              TeamWallet        = address(uint160(0xAAAA003A602));
    address                                 public              Owner             = address(uint160(0xAABBCC0000));
    address                                 public              NextUserBurner    = address(uint160(0xCC00220000));
    address                                 public              FundWallet        = address(uint160(0xBBB0000FFFF));


    function setUp() public {
        //100_00 - 100%
        vm.startPrank(Owner);
        TokenContract = new ReflectDebug(5_00, 50_00, TeamWallet, 10_000_000_000 ether);
        vm.stopPrank();

        RewardWallet = address(TokenContract);

        console.log("                     $REFLECT: %s", address(TokenContract));
        
        vm.startPrank(Owner);
        TokenContract.ExcludeWalletFromRewards(FundWallet);
        TokenContract.transferFrom(address(TokenContract), FundWallet, 10_000_000_000 ether);
        vm.stopPrank();
    }

    struct MerkelTree {
        bytes32[] flatTree;
        uint256[] lvlLength;
        uint256[] lvlIndexes;
    }

    function _toDecimalString(uint256 value, uint256 decimals) private pure returns (string memory) {
        unchecked {
            uint256 intLength = Math.log10(value) + 1;
            if (intLength <= decimals)
                intLength = 1;
            else
                intLength -= decimals;

            string memory decimalsTmpBuf = new string(decimals);
            uint256 decimalsLen = decimals;
         
            /// @solidity memory-safe-assembly
            assembly {
                let lenInc := not(0)
                let ptrStart := add(decimalsTmpBuf, 32)
                let ptr := add(ptrStart, decimals)

                for {} xor(ptrStart, ptr) {} {
                    ptr := add(ptr, not(0)) //-1

                    let remainder := mod(value, 10)
                    mstore8(ptr, byte(remainder, HEX_DIGITS))

                    if remainder {
                        lenInc := 0
                    }

                    decimalsLen := add(decimalsLen, lenInc) // -1 or -0
                    value := div(value, 10)
                }

                if iszero(decimalsLen) {
                    decimalsLen := 1
                }
            }

            string memory buffer = new string(intLength + decimalsLen + 1);

            
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, intLength))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }

            bytes memory decimalsBytesBuff;
            bytes memory resultBytesBuff;

            assembly {
                decimalsBytesBuff := decimalsTmpBuf
                resultBytesBuff := buffer
            }

            resultBytesBuff[intLength] = 0x2e; // "."

            for (uint256 i = 0; i < decimalsLen; i++) {
                resultBytesBuff[intLength + 1 + i] = decimalsBytesBuff[i];
            }

            return buffer;
        }
    }


    function _printWalletBalance(address wallet) private view {
        console.log();
        console.log(" Balances for %s", wallet);

        uint256 balance = TokenContract.balanceOf(wallet);
        console.log("     $REFLECT: %s [%d]", _toDecimalString(balance, 18), balance);
        console.log();
    }

    function _allocateBurner() private returns (address) {
        address burner = NextUserBurner;

        NextUserBurner = address(uint160(burner) + 1);

        return burner;
    }

    function _fundWallet(address wallet, uint256 amount) private {      
        _fundWallet(wallet, amount, true);
    }

    function _fundWallet(address wallet, uint256 amount, bool verbose) private {        
        if (verbose)
            console.log("Airdropping %s[%d] to %s", _toDecimalString(amount, 18), amount, wallet);
        uint256 oldUserbalance = TokenContract.balanceOf(wallet);
        if (verbose)
            _printWalletBalance(wallet);


        vm.startPrank(FundWallet);
        TokenContract.transfer(wallet, amount);
        vm.stopPrank();

        if (verbose)
            _printWalletBalance(wallet);

        uint256 newUserbalance = TokenContract.balanceOf(wallet);
        assertEq(amount, newUserbalance - oldUserbalance, "User balance change must be equal airdrop size");
    }

    /**
     * @dev Sorts the pair (a, b) and hashes the result.
     */
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    /**
     * @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
     */
    function _efficientHash(address a, uint256 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    /**
     * @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
     */
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _getMerkletreeNode(MerkelTree memory tree, uint256 level, uint256 index) private pure returns(bytes32) {
        require(level < tree.lvlIndexes.length, "requested level doesn't exist");
        require(index < tree.lvlLength[level], "Out of bounds for requested level");

        return tree.flatTree[tree.lvlIndexes[level] + index];
    }

    function _generateAirdropMerkleTree(address[] memory dests, uint256[] memory sizes) private pure returns(MerkelTree memory) {
        require(dests.length == sizes.length, "wrong input length");

        MerkelTree memory tree;

        {
            uint256 lvlDepth = Math.log2(dests.length, Math.Rounding.Expand) + 1;

            tree.lvlLength = new uint256[](lvlDepth);            
            tree.lvlIndexes = new uint256[](lvlDepth);

            uint256 evenLength = dests.length;
            if (evenLength > 1 )
                evenLength += evenLength & 1;

            tree.lvlLength[0] = evenLength;
            tree.lvlIndexes[0] = 0;

            for (uint256 i = 1; i < tree.lvlLength.length; i++) {
                tree.lvlIndexes[i] = tree.lvlIndexes[i - 1] + tree.lvlLength[i - 1];

                uint256 newLen = tree.lvlLength[i - 1] / 2;
                tree.lvlLength[i] = newLen + (newLen & 1);

            }

            tree.lvlLength[tree.lvlLength.length - 1] = 1;
            tree.flatTree = new bytes32[](tree.lvlIndexes[tree.lvlLength.length - 1] + 1);
        }

        for (uint256 i = 0; i < tree.lvlLength[0]; i++) {
            if (i < dests.length) {
                tree.flatTree[i] = _efficientHash(dests[i], sizes[i]);
            } else {
                tree.flatTree[i] = tree.flatTree[i - 1];
            }
        }

        for (uint256 lvl = 1; lvl < tree.lvlLength.length; lvl++) {
            uint256 lvlOffset = tree.lvlIndexes[lvl];
            uint256 downLvlLen = tree.lvlLength[lvl - 1];

            for (uint256 i = 0; i < tree.lvlLength[lvl]; i++) {
                if (i * 2 < downLvlLen) {
                    tree.flatTree[lvlOffset + i] = _hashPair(
                        _getMerkletreeNode(tree, lvl - 1, i * 2),
                        _getMerkletreeNode(tree, lvl - 1, i * 2 + 1)
                    );
                } else {
                    tree.flatTree[lvlOffset + i] = tree.flatTree[lvlOffset + i - 1];
                }
            }            
        }

        return tree;
    }

    function _extractMerkleProof(MerkelTree memory tree, uint256 item) private pure returns(bytes32[] memory) {
        require(item < tree.lvlLength[0]);

        bytes32[] memory proof = new bytes32[](tree.lvlLength.length - 1);

        for (uint256 i = 0; i < proof.length; i++) {
            if (item & 1 == 1) {
                proof[i] = _getMerkletreeNode(tree, i, item - 1);
            } else {
                proof[i] = _getMerkletreeNode(tree, i, item + 1);
            }

            item /= 2;
        }

        return proof;
    }


    function testTransferRegular() public {
        address srcUser = _allocateBurner();
        address dstUser = _allocateBurner();

        uint256 size = 1234 * 1e18;
        uint256 transferSize = 234 * 1e18;

        _fundWallet(srcUser, size);

        vm.startPrank(srcUser);
        TokenContract.transfer(dstUser, transferSize);
        vm.stopPrank();


        _printWalletBalance(srcUser);
        _printWalletBalance(dstUser);

        uint256 srcBalance = TokenContract.balanceOf(srcUser);
        uint256 dstBalance = TokenContract.balanceOf(dstUser);

        assertEq(size - transferSize, srcBalance, "Source wallet balance must be Origin - Transfer");
        assertEq(transferSize, dstBalance, "Destination wallet balance must be Transfer");
    }

    function testApprovalRegular() public {
        address srcUser = _allocateBurner();
        address delegateUser = _allocateBurner();
        address dstUser = _allocateBurner();


        uint256 size = 1234 * 1e18;
        uint256 transferSize = 234 * 1e18;

        _fundWallet(srcUser, size);

        vm.startPrank(srcUser);
        TokenContract.approve(delegateUser, transferSize);
        vm.stopPrank();

        assertEq(transferSize, TokenContract.allowance(srcUser, delegateUser), "Wrong allowance1");


        vm.startPrank(delegateUser);
        TokenContract.transferFrom(srcUser, dstUser, transferSize);
        vm.stopPrank();

        assertEq(0, TokenContract.allowance(srcUser, delegateUser), "Wrong allowance2");

        _printWalletBalance(srcUser);
        _printWalletBalance(dstUser);

        uint256 srcBalance = TokenContract.balanceOf(srcUser);
        uint256 dstBalance = TokenContract.balanceOf(dstUser);

        assertEq(size - transferSize, srcBalance, "Source wallet balance must be Origin - Transfer");
        assertEq(transferSize, dstBalance, "Destination wallet balance must be Transfer");
    }

    function testApprovalMax() public {
        address srcUser = _allocateBurner();
        address delegateUser = _allocateBurner();
        address dstUser = _allocateBurner();


        uint256 size = 1234 * 1e18;
        uint256 transferSize = 234 * 1e18;

        _fundWallet(srcUser, size);

        vm.startPrank(srcUser);
        TokenContract.approve(delegateUser, type(uint256).max);
        vm.stopPrank();

        assertEq(type(uint256).max, TokenContract.allowance(srcUser, delegateUser), "Wrong allowance3");


        vm.startPrank(delegateUser);
        TokenContract.transferFrom(srcUser, dstUser, transferSize);
        vm.stopPrank();

        assertEq(type(uint256).max, TokenContract.allowance(srcUser, delegateUser), "Wrong allowance4");

        _printWalletBalance(srcUser);
        _printWalletBalance(dstUser);

        uint256 srcBalance = TokenContract.balanceOf(srcUser);
        uint256 dstBalance = TokenContract.balanceOf(dstUser);

        assertEq(size - transferSize, srcBalance, "Source wallet balance must be Origin - Transfer");
        assertEq(transferSize, dstBalance, "Destination wallet balance must be Transfer");
    }

    function testAddressWhitelisting() public {
        address whitelistTestAddr = _allocateBurner();

        assertEq(false, TokenContract.Taxable(whitelistTestAddr), "init tax status");

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(whitelistTestAddr, true);
        vm.stopPrank();

        assertEq(true, TokenContract.Taxable(whitelistTestAddr), "switched on tax status");


        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(whitelistTestAddr, false);
        vm.stopPrank();

        assertEq(false, TokenContract.Taxable(whitelistTestAddr), "switched off tax status");

    }

    function testTaxConfig() public {
        address newTeamWallet = _allocateBurner();

        _fundWallet(TeamWallet, 34 * 1e18);
        

        vm.startPrank(Owner);
        TokenContract.UpdateTeamWallet(newTeamWallet);
        vm.stopPrank();

        _printWalletBalance(newTeamWallet);

        assertEq(34 * 1e18, TokenContract.balanceOf(newTeamWallet));


        uint16 newTax = 6_00;
        uint16 newRewardShare = 45_00;

        assertNotEq(newTax, TokenContract.Tax(), "tax is same, update the test!");
        assertNotEq(newRewardShare, TokenContract.RewardShare(), "tax share 1 is same, update the test!");


        vm.startPrank(Owner);
        TokenContract.SetTaxRatio(newTax, newRewardShare);
        vm.stopPrank();

        assertEq(newTax, TokenContract.Tax(), "tax setting ignored");
        assertEq(newRewardShare, TokenContract.RewardShare(), "tax share 1 setting ignored");
    }


    function testTaxCollection() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        vm.stopPrank();


        _fundWallet(user1, 200_0 * 1e18);
        _fundWallet(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(  2_5 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 1");
        assertEq(  2_5 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 1");

        uint96 taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  2_5 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 2");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 2");

        taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  5_0 * 1e18, taxed, "rew cycle taxed 2");

        
        console.log("Tax on from");
        
        address wasteWallet = _allocateBurner();
        vm.startPrank(taxable);
        TokenContract.transfer(wasteWallet, 100_0 * 1e18);
        vm.stopPrank();

        
        _printWalletBalance(taxable);
        _printWalletBalance(wasteWallet);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq( 90_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 3");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(wasteWallet), "waste balance");
        assertEq(  7_5 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 3");
        assertEq(  7_5 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 3");
        
        taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  7_5 * 1e18, taxed, "rew cycle taxed 3");
    }

    function testTaxCollectionOn0Tax() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        TokenContract.SetTaxRatio(0, TokenContract.RewardShare());
        vm.stopPrank();


        _fundWallet(user1, 200_0 * 1e18);
        _fundWallet(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq(100_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 1");

        uint96 taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(200_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 2");

        taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 2");
    }

    function testTaxCollectionOn0Share() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        TokenContract.SetTaxRatio(TokenContract.Tax(), 0);
        vm.stopPrank();


        _fundWallet(user1, 200_0 * 1e18);
        _fundWallet(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 1");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 1");

        uint96 taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 2");
        assertEq( 10_0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 2");

        taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 2");
    }

    function testTaxCollectionOn100Share() public {

        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        TokenContract.SetTaxRatio(TokenContract.Tax(), 100_00);
        vm.stopPrank();


        _fundWallet(user1, 200_0 * 1e18);
        _fundWallet(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 1");

        uint96 taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  5_0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(RewardWallet);
        _printWalletBalance(TeamWallet);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq( 10_0 * 1e18, TokenContract.balanceOf(RewardWallet), "tax1 balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TeamWallet), "tax2 balance 2");

        taxed = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq( 10_0 * 1e18, taxed, "rew cycle taxed 2");
    }



    struct _airDropTieringState {
        address[]  users;
        uint256[]  sizes;
        uint8[]    tiers;
        uint256    totalAirdrop;
        bytes32    root;

        MerkelTree tree;
    }

    function testTransferRetiering() public {
        _airDropTieringState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tiers = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (1_5000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_0000 * lState.totalAirdrop) / 100_0000;
        lState.tiers[0] = 0;
        lState.tiers[1] = 0;

        lState.sizes[2] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.tiers[2] = 1;
        lState.tiers[3] = 1;
        
        lState.sizes[4] =    (  4000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[5] =    (  3000 * lState.totalAirdrop) / 100_0000;
        lState.tiers[4] = 2;
        lState.tiers[5] = 2;
        
        lState.sizes[6] =    (  1000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[7] =    (   900 * lState.totalAirdrop) / 100_0000;
        lState.tiers[6] = 3;
        lState.tiers[7] = 3;
    
        lState.sizes[8] =    (   700 * lState.totalAirdrop) / 100_0000;
        lState.sizes[9] =    (   600 * lState.totalAirdrop) / 100_0000;
        lState.tiers[8] = 4;
        lState.tiers[9] = 4;
        
        lState.sizes[10] =   (   400 * lState.totalAirdrop) / 100_0000;
        lState.sizes[11] =   (   300 * lState.totalAirdrop) / 100_0000;
        lState.tiers[10] = 5;
        lState.tiers[11] = 5;
        
        lState.sizes[12] =   (   100 * lState.totalAirdrop) / 100_0000;
        lState.sizes[13] =   (    90 * lState.totalAirdrop) / 100_0000;
        lState.tiers[12] = 6;
        lState.tiers[13] = 6;
        
        lState.sizes[14] =   (    60 * lState.totalAirdrop) / 100_0000;
        lState.sizes[15] =   (    50 * lState.totalAirdrop) / 100_0000;
        lState.tiers[14] = 7;
        lState.tiers[15] = 7;
        
        lState.sizes[16] =   (    40 * lState.totalAirdrop) / 100_0000;
        lState.sizes[17] =   (    30 * lState.totalAirdrop) / 100_0000;
        lState.tiers[16] = type(uint8).max;
        lState.tiers[17] = type(uint8).max;

        lState.sizes[18] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);

            if (lState.tiers[i] != type(uint8).max) {
                RewardCycleStat memory tierStat = TokenContract.GetRewardCycleStat(TokenContract.CurrentRewardCycle(), lState.tiers[i]);

      
                console.log("Tier %d stat: regular: %d, boosted: %d", lState.tiers[i], tierStat.regularMembers, tierStat.boostedMembers);
                assertEq(1 + (i & 1), tierStat.regularMembers, "reg Membs");
                assertEq(0, tierStat.boostedMembers, "bst Membs");
            }


            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tier 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[15]); // -> moving to tier7
        vm.stopPrank();

        {
            RewardCycleStat memory tierStat = TokenContract.GetRewardCycleStat(TokenContract.CurrentRewardCycle(), 0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", tierStat.regularMembers, tierStat.boostedMembers);
            assertEq(2, tierStat.regularMembers, "reg Membs");
            assertEq(0, tierStat.boostedMembers, "bst Membs");

            tierStat = TokenContract.GetRewardCycleStat(TokenContract.CurrentRewardCycle(), 7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", tierStat.regularMembers, tierStat.boostedMembers);
            assertEq(3, tierStat.regularMembers, "reg Membs 2");
            assertEq(0, tierStat.boostedMembers, "bst Membs 2");
        }

        console.log("move outside tiers");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[15] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        {
            RewardCycleStat memory tierStat = TokenContract.GetRewardCycleStat(TokenContract.CurrentRewardCycle(), 0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", tierStat.regularMembers, tierStat.boostedMembers);
            assertEq(2, tierStat.regularMembers, "reg Membs");
            assertEq(0, tierStat.boostedMembers, "bst Membs");

            tierStat = TokenContract.GetRewardCycleStat(TokenContract.CurrentRewardCycle(), 7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", tierStat.regularMembers, tierStat.boostedMembers);
            assertEq(2, tierStat.regularMembers, "reg Membs 2");
            assertEq(0, tierStat.boostedMembers, "bst Membs 2");
        }
    }




    struct _rewardDistroState {
        address[]  users;
        uint256[]  sizes;
        uint256    totalAirdrop;
        address    taxedWallet;
        uint256[]  oldBalances;
    }


    function testTaxRewardDistro() public {
        _rewardDistroState memory lState;

        lState.users       = new address[](5);
        lState.sizes       = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length - 1);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (2_0000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_9000 * lState.totalAirdrop) / 100_0000;

        lState.sizes[2] =    (  9000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  8000 * lState.totalAirdrop) / 100_0000;


        lState.sizes[4] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[4] -= lState.sizes[i];
        }

        lState.taxedWallet = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        vm.stopPrank();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        console.log();
        console.log("==================================================================");
        console.log("                           TRANSFERS");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            vm.startPrank(lState.users[i]);
            TokenContract.transfer(lState.taxedWallet, 100 ether);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
        }

        _printWalletBalance(RewardWallet);
        // 100  eth* 2.5% * 4 = 100 eth * 10% = 10 eth
        assertEq(10 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance");


        for (uint256 i = 0; i < lState.oldBalances.length; i++) {
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        assertEq(0, TokenContract.CurrentRewardCycle(), "reward cycle ind 1");

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(1, TokenContract.CurrentRewardCycle(), "reward cycle ind 2");

        console.log();
        console.log("==================================================================");
        console.log("                           REWARDED BALANCES");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            _printWalletBalance(lState.users[i]);
        }

        // 10 eth * 30% * 50% = 1.5 eth
        assertEq(1_5 * 1e17, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(1_5 * 1e17, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");

        // 10 eth * 23% * 50% = 1.15 eth
        assertEq(1_15 * 1e16, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(1_15 * 1e16, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            TokenContract.balanceOfWithUpdate(lState.users[i]);
        }
        // 10 eth - 30% - 23% = 10 eth - 53% = 4.7 eth
        assertEq(4.7 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 2");
    }



    function testTaxRewardDistroBoosted() public {
        _rewardDistroState memory lState;

        lState.users = new address[](5);
        lState.sizes = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length - 1);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (2_0000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_9000 * lState.totalAirdrop) / 100_0000;

        lState.sizes[2] =    (  9000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  8000 * lState.totalAirdrop) / 100_0000;


        lState.sizes[4] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[4] -= lState.sizes[i];
        }

        lState.taxedWallet = _allocateBurner();


        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        vm.stopPrank();


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

    
        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[0]);
        vm.stopPrank();

        console.log();
        console.log("==================================================================");
        console.log("                           TRANSFERS");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            vm.startPrank(lState.users[i]);
            TokenContract.transfer(lState.taxedWallet, 100 ether);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
        }

        _printWalletBalance(RewardWallet);
        // 100  eth* 2.5% * 4 = 100 eth * 10% = 10 eth
        assertEq(10 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance");


        for (uint256 i = 0; i < lState.oldBalances.length; i++) {
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        assertEq(0, TokenContract.CurrentRewardCycle(), "reward cycle ind 1");

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(1, TokenContract.CurrentRewardCycle(), "reward cycle ind 2");

        console.log();
        console.log("==================================================================");
        console.log("                           REWARDED BALANCES");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            _printWalletBalance(lState.users[i]);
        }

        // 10 eth * 30% * 50.50% = 1.515 eth
        // 10 eth * 30% * 49.50% = 1.485 eth
        assertEq(1_515 * 1e15, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(1_485 * 1e15, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");

        // 10 eth * 23% * 50% = 1.15 eth
        assertEq(1_15 * 1e16, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(1_15 * 1e16, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            TokenContract.balanceOfWithUpdate(lState.users[i]);
        }
        // 10 eth - 30% - 23% = 10 eth - 53% = 4.7 eth
        assertEq(4.7 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 2");
    }
    
    function testDoubleActionBoostAccount() public {
        console.log("boosting account");

        vm.startPrank(Owner);
        TokenContract.BoostWallet(address(0xabcdef));
        vm.stopPrank();

        console.log("boosting account 2nd time");

        vm.startPrank(Owner);
        vm.expectRevert(bytes("Account could be boosted only once"));
        TokenContract.BoostWallet(address(0xabcdef));
        vm.stopPrank();
    }

    function testOwnerAccess() public {
        vm.startPrank(address(0xface00add));

        bytes memory revertExptMsg = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0xface00add));



        console.log("LaunchNewRewardCycle");
        vm.expectRevert(revertExptMsg);
        TokenContract.LaunchNewRewardCycle();

        console.log("SetTaxRatio");
        vm.expectRevert(revertExptMsg);
        TokenContract.SetTaxRatio(1,1);

        console.log("UpdateTeamWallet");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateTeamWallet(address(1));

        console.log("UpdateWhitelisting");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateWhitelisting(address(1), true);

        console.log("DisableReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.DisableReward(bytes32(uint256(2)));

        console.log("DistributeReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.DistributeReward(new address[](0), new uint256[](0), 1);

        console.log("BoostWallet");
        vm.expectRevert(revertExptMsg);
        TokenContract.BoostWallet(address(1));

        console.log("SwicthAutoTaxDistribution");
        vm.expectRevert(revertExptMsg);
        TokenContract.SwicthAutoTaxDistribution(true);


        console.log("ExcludeWalletFromRewards");
        vm.expectRevert(revertExptMsg);
        TokenContract.ExcludeWalletFromRewards(address(1));

        console.log("ProcessRewardsForUser");
        vm.expectRevert(revertExptMsg);
        TokenContract.ProcessRewardsForUser(address(1), 1);

        vm.stopPrank();
    }


    struct _multiRewardDistroState {
        address[]  users;
        address[]  taxSrcUsers;
        uint256[]  sizes;
        uint256    totalAirdrop;
        address    taxedWallet;
        uint256[]  oldBalances;
    }

    function testMultipleRewardCycleAccounting() public {
        _multiRewardDistroState memory lState;

        lState.users = new address[](4);
        lState.sizes = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length);

        lState.taxSrcUsers = new address[](50);

        
        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        lState.sizes[0] =    (1_0000 * lState.totalAirdrop) / 100_0000 - 100; //2nd tier
        lState.sizes[1] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[2] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;

        lState.taxedWallet = _allocateBurner();

        for (uint256 i = 0; i < lState.taxSrcUsers.length; i++) {
            lState.taxSrcUsers[i] = _allocateBurner();
        }

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        vm.stopPrank();


        for (uint256 i = 0; i < lState.users.length; i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        for (uint256 i = 0; i < lState.taxSrcUsers.length; i++) {
            _fundWallet(lState.taxSrcUsers[i], 100 ether, false);
        }

        
        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[1]);
        vm.stopPrank();


        for(uint256 i = 0; i < 10; i++) {
            vm.startPrank(lState.taxSrcUsers[i]);
            TokenContract.transfer(lState.taxedWallet, 10 ether);
            vm.stopPrank();
        }

        //taxed reward = 10 ether * 10 * 2.5% = 100 * 2.5% = 2.5 ether

        for (uint256 i = 0; i < lState.oldBalances.length; i++) {
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        assertEq(0, TokenContract.CurrentRewardCycle(), "reward cycle ind 1");

        console.log("Reward cycle 1");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(1, TokenContract.CurrentRewardCycle(), "reward cycle ind 2");

        // 2.5 eth * 23% * 24.75% = 0.1423125 ether
        // 2.5 eth * 23% * 25.75% = 0.1480625 ether
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(1480625 * 1e11, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");



        for(uint256 i = 0; i < 10; i++) {
            vm.startPrank(lState.taxSrcUsers[i + 10]);
            TokenContract.transfer(lState.taxedWallet, 20 ether);
            vm.stopPrank();
        }

        //taxed reward = 20 ether * 10 * 2.5% = 200 * 2.5% = 5 ether
 
        console.log("Reward cycle 2");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(2, TokenContract.CurrentRewardCycle(), "reward cycle ind 3");

        // (2.5 eth + 5 eth) * 23% * 24.75% = 0.4269375 ether
        // (2.5 eth + 5 eth) * 23% * 25.75% = 0.4441875 ether
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(4441875 * 1e11, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");
        
        
        for (uint256 i = 0; i < lState.users.length; i++) {
            address user = lState.users[i];
            uint256 gasBefore = gasleft();
            TokenContract.balanceOfWithUpdate(user);
            uint256 gasAfter = gasleft();

            console.log("Gas usage by balanceOfWithUpdate (2 rew cycles): %d", gasBefore - gasAfter);

            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        
        // 7.5 eth - 23% = 5.775 eth
        assertEq(5.775 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 1");

        for(uint256 i = 0; i < 4; i++) {
            vm.startPrank(lState.taxSrcUsers[i + 20]);
            TokenContract.transfer(lState.taxedWallet, 100 ether);
            vm.stopPrank();
        }

        //taxed reward = 100 ether * 4 * 2.5% = 100 * 10% = 10 ether


        
        console.log("Reward cycle 3");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        // 10 eth * 30% * 100% = 3 eth
        // 10 eth * 23% * 33% = 0.759 ether
        // 10 eth * 23% * 34% = 0.782 ether
        assertEq(3_000 * 1e15, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(  782 * 1e15, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(  759 * 1e15, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(  759 * 1e15, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");

        

        
        for (uint256 i = 0; i < lState.users.length; i++) {
            address user = lState.users[i];
            uint256 gasBefore = gasleft();
            TokenContract.balanceOfWithUpdate(user);
            uint256 gasAfter = gasleft();

            console.log("Gas usage by balanceOfWithUpdate (1 rew cycles): %d", gasBefore - gasAfter);
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        // (7.5 eth - 23%) + 
        // + (10 eth - 30% - 23%) = 5.775 eth + (10 eth - 53%) = 5.775 eth + 4.7 eth = 10.475 eth
        assertEq(10.475 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 2");
    }


    function testMultipleLowTierRewardCycleAccounting() public {
        _multiRewardDistroState memory lState;

        lState.users = new address[](4);
        lState.sizes = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length);

        lState.taxSrcUsers = new address[](50);

        
        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        lState.sizes[0] =    (    50 * lState.totalAirdrop) / 100_0000; //last tier
        lState.sizes[1] =    (    50 * lState.totalAirdrop) / 100_0000;
        lState.sizes[2] =    (    50 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (    50 * lState.totalAirdrop) / 100_0000;

        lState.taxedWallet = _allocateBurner();

        for (uint256 i = 0; i < lState.taxSrcUsers.length; i++) {
            lState.taxSrcUsers[i] = _allocateBurner();
        }

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        vm.stopPrank();


        for (uint256 i = 0; i < lState.users.length; i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        for (uint256 i = 0; i < lState.taxSrcUsers.length; i++) {
            _fundWallet(lState.taxSrcUsers[i], 100 ether, false);
        }

        
        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[1]);
        vm.stopPrank();


        for(uint256 i = 0; i < 10; i++) {
            vm.startPrank(lState.taxSrcUsers[i]);
            TokenContract.transfer(lState.taxedWallet, 10 ether);
            vm.stopPrank();
        }

        //taxed reward = 10 ether * 10 * 2.5% = 100 * 2.5% = 2.5 ether

        for (uint256 i = 0; i < lState.oldBalances.length; i++) {
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        assertEq(0, TokenContract.CurrentRewardCycle(), "reward cycle ind 1");

        console.log("Reward cycle 1");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(1, TokenContract.CurrentRewardCycle(), "reward cycle ind 2");

        /*/
        // 2.5 eth * 23% * 24.75% = 0.1423125 ether
        // 2.5 eth * 23% * 25.75% = 0.1480625 ether
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(1480625 * 1e11, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(1423125 * 1e11, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");
        //*/



        for(uint256 i = 0; i < 10; i++) {
            vm.startPrank(lState.taxSrcUsers[i + 10]);
            TokenContract.transfer(lState.taxedWallet, 20 ether);
            vm.stopPrank();
        }

        //taxed reward = 20 ether * 10 * 2.5% = 200 * 2.5% = 5 ether
 
        console.log("Reward cycle 2");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        assertEq(2, TokenContract.CurrentRewardCycle(), "reward cycle ind 3");

        /*
        // (2.5 eth + 5 eth) * 23% * 24.75% = 0.4269375 ether
        // (2.5 eth + 5 eth) * 23% * 25.75% = 0.4441875 ether
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(4441875 * 1e11, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(4269375 * 1e11, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");
        //*/
        
        
        for (uint256 i = 0; i < lState.users.length; i++) {
            address user = lState.users[i];
            uint256 gasBefore = gasleft();
            TokenContract.balanceOfWithUpdate(user);
            uint256 gasAfter = gasleft();

            console.log("Gas usage by balanceOfWithUpdate (2 rew cycles): %d", gasBefore - gasAfter);

            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        
        // 7.5 eth - 23% = 5.775 eth
        //assertEq(5.775 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 1");

        for(uint256 i = 0; i < 4; i++) {
            vm.startPrank(lState.taxSrcUsers[i + 20]);
            TokenContract.transfer(lState.taxedWallet, 100 ether);
            vm.stopPrank();
        }

        //taxed reward = 100 ether * 4 * 2.5% = 100 * 10% = 10 ether


        
        console.log("Reward cycle 3");
        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        /*
        // 10 eth * 30% * 100% = 3 eth
        // 10 eth * 23% * 33% = 0.759 ether
        // 10 eth * 23% * 34% = 0.782 ether
        assertEq(3_000 * 1e15, TokenContract.balanceOf(lState.users[0]) - lState.oldBalances[0], "assigned reward 0");
        assertEq(  782 * 1e15, TokenContract.balanceOf(lState.users[1]) - lState.oldBalances[1], "assigned reward 1");
        assertEq(  759 * 1e15, TokenContract.balanceOf(lState.users[2]) - lState.oldBalances[2], "assigned reward 2");
        assertEq(  759 * 1e15, TokenContract.balanceOf(lState.users[3]) - lState.oldBalances[3], "assigned reward 3");
        //*/

        

        
        for (uint256 i = 0; i < lState.users.length; i++) {
            address user = lState.users[i];
            uint256 gasBefore = gasleft();
            TokenContract.balanceOfWithUpdate(user);
            uint256 gasAfter = gasleft();

            console.log("Gas usage by balanceOfWithUpdate (1 rew cycles): %d", gasBefore - gasAfter);
            lState.oldBalances[i] = TokenContract.balanceOf(lState.users[i]);
        }

        // (7.5 eth - 23%) + 
        // + (10 eth - 30% - 23%) = 5.775 eth + (10 eth - 53%) = 5.775 eth + 4.7 eth = 10.475 eth
        //assertEq(10.475 ether, TokenContract.balanceOf(RewardWallet), "Tax auth 1 balance 2");
    }
}