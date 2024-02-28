// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ReflectDebug} from "../src/ReflectErc20Debug.sol";
import "../src/ReflectDataModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


bytes16 constant HEX_DIGITS = "0123456789abcdef";

contract CounterTest is Test {


    
    ReflectDebug                            public              TokenContract;

    address                                 public              TaxAuth1        = address(uint160(0xAAAA003A601));
    address                                 public              TaxAuth2        = address(uint160(0xAAAA003A602));
    address                                 public              Owner           = address(uint160(0xAABBCC0000));
    address                                 public              NextUserBurner     = address(uint160(0xCC00220000));


    function setUp() public {
        //100_00 - 100%
        vm.startPrank(Owner);
        TokenContract = new ReflectDebug(5_00, 50_00, TaxAuth1, TaxAuth2);
        vm.stopPrank();

        console.log("                     $REFLECT: %s", address(TokenContract));
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

    function _airDropTargeted(address wallet, uint256 amount) private {        
        console.log("Airdropping %s[%d] to %s", _toDecimalString(amount, 18), amount, wallet);
        vm.startPrank(Owner);        

        uint256 oldUserbalance = TokenContract.balanceOf(wallet);

        _printWalletBalance(wallet);

        TokenContract.PrepareAirdrop(bytes32(uint256(1)), amount, 20_000);
        //TODO: more indexing?
        TokenContract.IndexShadow(20_000);

        TokenContract.MintTo(wallet);
        vm.stopPrank();

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

    function _extractMerkleProof(MerkelTree memory tree, uint256 item) private view returns(bytes32[] memory) {
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

    function testAirdropSimple() public {
        address testUser = _allocateBurner();
        uint256 airdropSize = 1234 * 1e18;

        _printWalletBalance(testUser);
        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        console.log("Launching targeted airdrop");
        vm.startPrank(Owner);

        assertEq(0, TokenContract.LastShadowIndexedTireInvert(), "wrong invert tire (must be 0)");
        assertEq(0, TokenContract.LastShadowIndexedChunkInvert(), "wrong invert chunk (must be 0)");

        assertEq(bytes32(type(uint256).max), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0xff..ff)");
        assertEq(0, TokenContract.NextAirdrop(), "wrong airdrop size (must be 0)");

        assertEq(type(uint8).max, TokenContract.LastShadowIndexedTire(), "wrong tire (must be 0xff)");
        assertEq(type(uint16).max, TokenContract.LastShadowIndexedChunk(), "wrong chunk (must be 0xffff)");
        
        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 1");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 1");
        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 1");





        console.log("Prepare");
        TokenContract.PrepareAirdrop(bytes32(uint256(1)), airdropSize, 20_000);

        assertNotEq(0, TokenContract.LastShadowIndexedTireInvert(), "wrong invert tire (must be non 0)");
        assertNotEq(0, TokenContract.LastShadowIndexedChunkInvert(), "wrong invert chunk (must be non 0)");
        
        assertEq(bytes32(uint256(1)), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0x1)");
        assertEq(airdropSize, TokenContract.NextAirdrop(), "wrong airdrop size (must be airdropsize)");
        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 2");
        
        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 2");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 2");


        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());





        console.log("Index");
        TokenContract.IndexShadow(20_000);

        assertEq(FEE_TIRES, TokenContract.LastShadowIndexedTire(), "wrong tire (must be FEE_TIRES)");
        
        assertEq(bytes32(uint256(1)), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0x1)");
        assertEq(airdropSize, TokenContract.NextAirdrop(), "wrong airdrop size (must be airdropsize)");
        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 3");





        console.log("MintTo");
        TokenContract.MintTo(testUser);

        vm.stopPrank();
        
        assertEq(airdropSize, TokenContract.balanceOf(testUser), "User must get entire airdrop");
        assertEq(bytes32(type(uint256).max), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0xff..ff)"); 
        assertEq(1, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 4");       
        
        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 3");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 3");
         
        _printWalletBalance(testUser);
        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());


        console.log("Checking tire indexing");


        AccountState memory accountInfo = TokenContract.AccountData(testUser);

        {            
            console.log(" Account pointers");

            uint8 mintIndexTire = ~accountInfo.mintIndexTireInvert;
            uint16 mintIndexChunk = ~accountInfo.mintIndexChunkInvert;

            assertEq(0, mintIndexTire, "tire must be 0 as solid owner of token supply");
            assertEq(0, mintIndexChunk, "first drop can be only in first chunk");

            assertEq(0, accountInfo.shadowIndexTireInvert, "shadow index tire expected to be unitialised");
            assertEq(0, accountInfo.shadowIndexChunkInvert, "shadow index chunk expected to be unitialised");
            assertEq(0, accountInfo.shadowIndexId, "shadow index id expected to be unitialised");

            console.log(" Index contents");

            uint256 currentMintIndex = TokenContract.ActiveMintIndex();
            uint256 totalSupply = TokenContract.MintIndexes(currentMintIndex);

            assertEq(airdropSize, totalSupply, "First total supply must match airdrop size");



            console.log(" Tire contents");
            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 0);

            
            assertEq(1, regularLength, "tire regular memebers count must be 1");
            assertEq(0, highLength, "tire high reward memebers count must be 0");
            assertEq(1, chunksCount, "tire chunks count must be 1");


            console.log(" chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 0, 0);

            
            assertEq(1, chunkLen, "chunk length must be 1");
            assertEq(testUser, chunkList[0], "chunk list must starts with test user");
        }
    }

    function testAirdropSimple2Targets() public {        
        address testUser1 = _allocateBurner();
        address testUser2 = _allocateBurner();

        uint256 size1 = 1234*1e18;
        uint256 size2 = 4321*1e18;

        _airDropTargeted(testUser1, size1);
        _airDropTargeted(testUser2, size2);

        
        assertEq(size1, TokenContract.balanceOf(testUser1), "User1 must get entire airdrop");
        assertEq(size2, TokenContract.balanceOf(testUser2), "User2 must get entire airdrop");

        assertEq(size1 + size2, TokenContract.totalSupply(), "Total supply must be equal to 2 airdrops");
    }

    function testAirdropSimple1TMultiple() public {        
        address testUser1 = _allocateBurner();

        uint256 size1 = 1234*1e18;
        uint256 size2 = 4321*1e18;

        _airDropTargeted(testUser1, size1);
        _airDropTargeted(testUser1, size2);

        
        assertEq(size1 + size2, TokenContract.balanceOf(testUser1), "User1 must get entire airdrop");

        assertEq(size1 + size2, TokenContract.totalSupply(), "Total supply must be equal to 2 airdrops");
    }

    function testAirdropMerkle() public {
        address[] memory users = new address[](5);
        uint256[] memory sizes = new uint256[](5);
        uint256 totalAirdropSize = 0;

        for (uint256 i = 0; i < users.length; i++) {
            users[i] = _allocateBurner();
            sizes[i] = (i + 1) * 1e18;
            totalAirdropSize += (i + 1) * 1e18;
        }

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];

        /*{
            string memory space = " ";

            for (uint256 lvl = 0; lvl < tree.lvlLength.length; lvl++) {
                uint lvlLen = tree.lvlLength[tree.lvlLength.length - lvl - 1];

                bytes memory buffer = new bytes(0);

                for (uint256 i = 0; i < lvlLen; i++) {
                    string memory convertedLayer = vm.toString(_getMerkletreeNode(tree, tree.lvlLength.length - lvl - 1, i));

                    buffer = bytes.concat(buffer, bytes(convertedLayer), bytes(space));
                }

                console.log(string(buffer));
            }
        }//*/

        console.log("Root is:");
        console.logBytes32(root);
        
        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        console.log("Launching Merkle airdrop");

        assertEq(0, TokenContract.LastShadowIndexedTireInvert(), "wrong invert tire (must be 0)");
        assertEq(0, TokenContract.LastShadowIndexedChunkInvert(), "wrong invert chunk (must be 0)");

        assertEq(bytes32(type(uint256).max), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0xff..ff)");
        assertEq(0, TokenContract.NextAirdrop(), "wrong airdrop size (must be 0)");

        assertEq(type(uint8).max, TokenContract.LastShadowIndexedTire(), "wrong tire (must be 0xff)");
        assertEq(type(uint16).max, TokenContract.LastShadowIndexedChunk(), "wrong chunk (must be 0xffff)");

        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 1");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 1");

        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 1");




        console.log("Prepare");
        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(root, totalAirdropSize, 20_000);

        assertNotEq(0, TokenContract.LastShadowIndexedTireInvert(), "wrong invert tire (must be non 0)");
        assertNotEq(0, TokenContract.LastShadowIndexedChunkInvert(), "wrong invert chunk (must be non 0)");
        
        assertEq(root, TokenContract.NextAirdropRoot(), "wrong airdrop root (must be root)");
        assertEq(totalAirdropSize, TokenContract.NextAirdrop(), "wrong airdrop size (must be totalAirdropSize)");
        
        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 2");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 2");

        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 2");


        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());




        console.log("Index");
        TokenContract.IndexShadow(20_000);

        assertEq(FEE_TIRES, TokenContract.LastShadowIndexedTire(), "wrong tire (must be FEE_TIRES)");
        
        assertEq(root, TokenContract.NextAirdropRoot(), "wrong airdrop root (must be root)");
        assertEq(totalAirdropSize, TokenContract.NextAirdrop(), "wrong airdrop size (must be totalAirdropSize)");

        assertEq(0, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 3");
        assertEq(0, TokenContract.AirdropWaveRoots(root), "Airdrop wave before launch");





        console.log("LaunchAirdrop");
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        assertEq(bytes32(type(uint256).max), TokenContract.NextAirdropRoot(), "wrong airdrop root (must be 0xff..ff)");
        assertEq(totalAirdropSize, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 3");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance 3");
        assertEq(totalAirdropSize, TokenContract.totalSupply());
        assertEq(totalAirdropSize , TokenContract.AirdropWaveRoots(root), "Airdrop wave after launch");

        assertEq(1, TokenContract.ActiveMintIndex(), "wrong ActiveMintIndex 4");

        {
            uint256 airdropped = 0;

            console.log("*************************** START CLAIMING **********************************");

            for (uint256 i = 0; i < users.length; i++) {
                bytes32[] memory proof = _extractMerkleProof(tree, i);
                
                _printWalletBalance(users[i]);
                assertEq(0, TokenContract.balanceOf(users[i]), "balance before airdrop");

                vm.startPrank(users[i]);
                TokenContract.Airdrop(root, proof, sizes[i]);
                vm.stopPrank();

                _printWalletBalance(users[i]);
                assertEq(sizes[i], TokenContract.balanceOf(users[i]), "balance after airdrop");

                airdropped += sizes[i];
                assertEq(totalAirdropSize - airdropped, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance 4");
                assertEq(totalAirdropSize - airdropped, TokenContract.AirdropWaveRoots(root), "Airdrop wave decrease");


                console.log("--------------------------------------- NEXT USER ------------------------------");
            }
            

            assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "Locked balance claim end");
            assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "Available balance claim end");

            _printWalletBalance(TokenContract.LockedMintAddress());
            _printWalletBalance(TokenContract.AvailableMintAddress());

            console.log("################################# CLAIM DONE ##########################");
        }


    }


    function testTransferRegular() public {
        address srcUser = _allocateBurner();
        address dstUser = _allocateBurner();

        uint256 size = 1234 * 1e18;
        uint256 transferSize = 234 * 1e18;

        _airDropTargeted(srcUser, size);

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

        _airDropTargeted(srcUser, size);

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

        _airDropTargeted(srcUser, size);

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

    }


    function testTransferRetireing() public {
        
    }

    function testTaxAccounting() public {

    }

    function testTaxRewardDistro() public {

    }    

    function testTaxConfig() public {

    }






    function testAirdropTiering() public{

    }

    //TODO: shadow index tests

}