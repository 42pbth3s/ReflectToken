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

            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            assertEq(0, mintIndexTire, "tire must be 0 as solid owner of token supply");
            assertEq(0, mintIndexChunk, "first drop can be only in first chunk");

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire expected to be unitialised");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk expected to be unitialised");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id expected to be unitialised");

            console.log(" Index contents");

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
                assertTrue(TokenContract.ClaimedAirdrop(tree.flatTree[i]), "Claim mark");


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
        address newAuth1 = _allocateBurner();
        address newAuth2 = _allocateBurner();

        _airDropTargeted(TaxAuth1, 12 * 1e18);
        _airDropTargeted(TaxAuth2, 34 * 1e18);
        

        vm.startPrank(Owner);
        TokenContract.UpdateTaxAuthorities(newAuth1, newAuth2);
        vm.stopPrank();

        _printWalletBalance(newAuth1);
        _printWalletBalance(newAuth2);

        assertEq(12 * 1e18, TokenContract.balanceOf(newAuth1));
        assertEq(34 * 1e18, TokenContract.balanceOf(newAuth2));


        uint16 newTax = 6_00;
        uint16 newShare1 = 45_00;

        assertNotEq(newTax, TokenContract.Tax(), "tax is same, update the test!");
        assertNotEq(newShare1, TokenContract.TaxAuth1Share(), "tax share 1 is same, update the test!");


        vm.startPrank(Owner);
        TokenContract.SetTaxRatio(newTax, newShare1);
        vm.stopPrank();

        assertEq(newTax, TokenContract.Tax(), "tax setting ignored");
        assertEq(newShare1, TokenContract.TaxAuth1Share(), "tax share 1 setting ignored");
    }


    function testTaxCollection() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        vm.stopPrank();


        _airDropTargeted(user1, 200_0 * 1e18);
        _airDropTargeted(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(  2_5 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 1");
        assertEq(  2_5 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 1");

        (uint96 taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  2_5 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 2");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 2");

        (taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  5_0 * 1e18, taxed, "rew cycle taxed 2");

        
        console.log("Tax on from");
        
        address wasteWallet = _allocateBurner();
        vm.startPrank(taxable);
        TokenContract.transfer(wasteWallet, 100_0 * 1e18);
        vm.stopPrank();

        
        _printWalletBalance(taxable);
        _printWalletBalance(wasteWallet);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq( 90_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 3");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(wasteWallet), "waste balance");
        assertEq(  7_5 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 3");
        assertEq(  7_5 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 3");
        
        (taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  7_5 * 1e18, taxed, "rew cycle taxed 3");
    }

    function testTaxCollectionOn0Tax() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);
        TokenContract.SetTaxRatio(0, TokenContract.TaxAuth1Share());
        vm.stopPrank();


        _airDropTargeted(user1, 200_0 * 1e18);
        _airDropTargeted(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq(100_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 1");

        (uint96 taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(200_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 2");

        (taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
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


        _airDropTargeted(user1, 200_0 * 1e18);
        _airDropTargeted(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 1");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 1");

        (uint96 taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(    0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 2");
        assertEq( 10_0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 2");

        (taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
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


        _airDropTargeted(user1, 200_0 * 1e18);
        _airDropTargeted(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");
        assertEq(  5_0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 1");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 1");

        (uint96 taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(  5_0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(TaxAuth1);
        _printWalletBalance(TaxAuth2);

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");
        assertEq( 10_0 * 1e18, TokenContract.balanceOf(TaxAuth1), "tax1 balance 2");
        assertEq(    0 * 1e18, TokenContract.balanceOf(TaxAuth2), "tax2 balance 2");

        (taxed, ) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq( 10_0 * 1e18, taxed, "rew cycle taxed 2");
    }



    struct _airDropTireingState {
        address[]  users;
        uint256[]  sizes;
        uint8[]    tires;
        uint256    totalAirdrop;
        bytes32    root;

        MerkelTree tree;
    }

    function testAirdropTiering() public{
        _airDropTireingState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tires = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (1_5000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_0000 * lState.totalAirdrop) / 100_0000;
        lState.tires[0] = 0;
        lState.tires[1] = 0;

        lState.sizes[2] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.tires[2] = 1;
        lState.tires[3] = 1;
        
        lState.sizes[4] =    (  4000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[5] =    (  3000 * lState.totalAirdrop) / 100_0000;
        lState.tires[4] = 2;
        lState.tires[5] = 2;
        
        lState.sizes[6] =    (  1000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[7] =    (   900 * lState.totalAirdrop) / 100_0000;
        lState.tires[6] = 3;
        lState.tires[7] = 3;
    
        lState.sizes[8] =    (   700 * lState.totalAirdrop) / 100_0000;
        lState.sizes[9] =    (   600 * lState.totalAirdrop) / 100_0000;
        lState.tires[8] = 4;
        lState.tires[9] = 4;
        
        lState.sizes[10] =   (   400 * lState.totalAirdrop) / 100_0000;
        lState.sizes[11] =   (   300 * lState.totalAirdrop) / 100_0000;
        lState.tires[10] = 5;
        lState.tires[11] = 5;
        
        lState.sizes[12] =   (   100 * lState.totalAirdrop) / 100_0000;
        lState.sizes[13] =   (    90 * lState.totalAirdrop) / 100_0000;
        lState.tires[12] = 6;
        lState.tires[13] = 6;
        
        lState.sizes[14] =   (    60 * lState.totalAirdrop) / 100_0000;
        lState.sizes[15] =   (    50 * lState.totalAirdrop) / 100_0000;
        lState.tires[14] = 7;
        lState.tires[15] = 7;
        
        lState.sizes[16] =   (    40 * lState.totalAirdrop) / 100_0000;
        lState.sizes[17] =   (    30 * lState.totalAirdrop) / 100_0000;
        lState.tires[16] = type(uint8).max;
        lState.tires[17] = type(uint8).max;

        lState.sizes[18] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];


        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);

            AccountState memory accountInfo = TokenContract.AccountData(lState.users[i]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();
        
            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(lState.tires[i], mintIndexTire, "user tire");
            if (lState.tires[i] != type(uint8).max)
                assertEq(0, mintIndexChunk, "user chunk");
            else
                assertEq(type(uint16).max, mintIndexChunk, "user chunk 2");

            //No shadows at first mint

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");

            
            if (lState.tires[i] != type(uint8).max) {
                console.log(" Tire contents");

                (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, lState.tires[i]);

                
                assertEq(1 + (i & 1), regularLength, "tire reg memb");
                assertEq(0, highLength, "tire high rewardmemb");
                assertEq(1, chunksCount, "tire chunks");


                console.log(" Chunk contents");
                (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, lState.tires[i], 0);

                
                assertEq(1 + (i & 1), chunkLen, "chunk length");
                assertEq(lState.users[i], chunkList[i & 1], "chunk list entry");
            }
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        console.log("Start checking shadow index & reshuffle");

        //Shifting everyhting on 0.001%
        {
            // 100_0000
            //   0_0010 -> 10
            //  99_9990

            uint256 extraSupply = (lState.totalAirdrop * 100_0000_0) / 99_9990; //an extra 10 for rounding up below

            if ((extraSupply % 10) != 0) {
                extraSupply += 10; // rounding up
            }
            extraSupply /= 10; //dropping last digit
            extraSupply -= lState.totalAirdrop;

            
            // Do not complete operation
            // to sanity check shadow index
            vm.startPrank(Owner);
            TokenContract.PrepareAirdrop(bytes32(uint256(1)), extraSupply, 20_000);
            TokenContract.IndexShadow(20_000);
            vm.stopPrank();
        }

        //start checking

        
        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[i]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert;
            uint24 shadowIndexId = accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId;

            console.log("User tire: %d ; chunk: %d ; indexId: %d", mintIndexTire, mintIndexChunk, shadowIndexId);

            if (lState.tires[i] != type(uint8).max) {
                uint8 expectedTire = lState.tires[i] + uint8(i & 1);
                if (expectedTire == FEE_TIRES)
                    expectedTire = type(uint8).max;

                assertEq(expectedTire, mintIndexTire, "user shadow tire");
                if (expectedTire != type(uint8).max) {
                    assertEq(2, shadowIndexId, "user shadow index 1");
                } else {
                    assertEq(0, shadowIndexId, "user shadow index 2");
                }
            } else {
                assertEq(0, shadowIndexId, "user shadow index 3");
            }
            console.log("------------------------ NEXT USER --------------------------");
        }

        //switching to main
        console.log("Switching shadow index to main");

        {
            address someUser = _allocateBurner();
        
            vm.startPrank(Owner);
            TokenContract.MintTo(someUser);
            vm.stopPrank();

            assertEq(2, TokenContract.ActiveMintIndex(), "mint index 2");
        }

        console.log("Validating main index");
        
        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[i]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            if (lState.tires[i] != type(uint8).max) {
                uint8 expectedTire = lState.tires[i] + uint8(i & 1);
                if (expectedTire == FEE_TIRES)
                    expectedTire = type(uint8).max;

                assertEq(expectedTire, mintIndexTire, "user shadow tire");
            }
            console.log("************************ NEXT USER **************************");
        }
    }


    function testTransferRetireing() public {
        _airDropTireingState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tires = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (1_5000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_0000 * lState.totalAirdrop) / 100_0000;
        lState.tires[0] = 0;
        lState.tires[1] = 0;

        lState.sizes[2] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.tires[2] = 1;
        lState.tires[3] = 1;
        
        lState.sizes[4] =    (  4000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[5] =    (  3000 * lState.totalAirdrop) / 100_0000;
        lState.tires[4] = 2;
        lState.tires[5] = 2;
        
        lState.sizes[6] =    (  1000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[7] =    (   900 * lState.totalAirdrop) / 100_0000;
        lState.tires[6] = 3;
        lState.tires[7] = 3;
    
        lState.sizes[8] =    (   700 * lState.totalAirdrop) / 100_0000;
        lState.sizes[9] =    (   600 * lState.totalAirdrop) / 100_0000;
        lState.tires[8] = 4;
        lState.tires[9] = 4;
        
        lState.sizes[10] =   (   400 * lState.totalAirdrop) / 100_0000;
        lState.sizes[11] =   (   300 * lState.totalAirdrop) / 100_0000;
        lState.tires[10] = 5;
        lState.tires[11] = 5;
        
        lState.sizes[12] =   (   100 * lState.totalAirdrop) / 100_0000;
        lState.sizes[13] =   (    90 * lState.totalAirdrop) / 100_0000;
        lState.tires[12] = 6;
        lState.tires[13] = 6;
        
        lState.sizes[14] =   (    60 * lState.totalAirdrop) / 100_0000;
        lState.sizes[15] =   (    50 * lState.totalAirdrop) / 100_0000;
        lState.tires[14] = 7;
        lState.tires[15] = 7;
        
        lState.sizes[16] =   (    40 * lState.totalAirdrop) / 100_0000;
        lState.sizes[17] =   (    30 * lState.totalAirdrop) / 100_0000;
        lState.tires[16] = type(uint8).max;
        lState.tires[17] = type(uint8).max;

        lState.sizes[18] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];


        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);

            AccountState memory accountInfo = TokenContract.AccountData(lState.users[i]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();
        
            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(lState.tires[i], mintIndexTire, "user tire");
            if (lState.tires[i] != type(uint8).max)
                assertEq(0, mintIndexChunk, "user chunk");
            else
                assertEq(type(uint16).max, mintIndexChunk, "user chunk 2");

            //No shadows at first mint

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");

            
            if (lState.tires[i] != type(uint8).max) {
                console.log(" Tire contents");

                (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, lState.tires[i]);

                
                assertEq(1 + (i & 1), regularLength, "tire reg memb");
                assertEq(0, highLength, "tire high rewardmemb");
                assertEq(1, chunksCount, "tire chunks");


                console.log(" Chunk contents");
                (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, lState.tires[i], 0);

                
                assertEq(1 + (i & 1), chunkLen, "chunk length");
                assertEq(lState.users[i], chunkList[i & 1], "chunk list entry");
            }
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tire 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[15]); // -> moving to tire7
        vm.stopPrank();

        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User 0 tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(7, mintIndexTire, "user tire");
            assertEq(0, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 7);

            
            assertEq(3, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 7, 0);

            
            assertEq(3, chunkLen, "chunk length");
            assertEq(lState.users[0], chunkList[2], "chunk list entry");
        }

        {
            AccountState memory accountInfo = TokenContract.AccountData(wasteWallet);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User waste tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(0, mintIndexTire, "user tire");
            assertEq(0, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 0);

            
            assertEq(2, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 0, 0);

            
            assertEq(2, chunkLen, "chunk length");
            assertEq(lState.users[1], chunkList[0], "chunk list entry 1");
            assertEq(wasteWallet, chunkList[1], "chunk list entry 2");
        }

        console.log("move outside tires");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[15] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User 0 tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(type(uint8).max, mintIndexTire, "user tire");
            assertEq(type(uint16).max, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 7);

            
            assertEq(2, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 7, 0);

            
            assertEq(2, chunkLen, "chunk length");
            assertEq(lState.users[14], chunkList[0], "chunk list entry");
            assertEq(lState.users[15], chunkList[1], "chunk list entry");
        }
    }


    function testTransferShadowRetireing() public {
        _airDropTireingState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tires = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (1_5000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_0000 * lState.totalAirdrop) / 100_0000;
        lState.tires[0] = 0;
        lState.tires[1] = 0;

        lState.sizes[2] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.tires[2] = 1;
        lState.tires[3] = 1;
        
        lState.sizes[4] =    (  4000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[5] =    (  3000 * lState.totalAirdrop) / 100_0000;
        lState.tires[4] = 2;
        lState.tires[5] = 2;
        
        lState.sizes[6] =    (  1000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[7] =    (   900 * lState.totalAirdrop) / 100_0000;
        lState.tires[6] = 3;
        lState.tires[7] = 3;
    
        lState.sizes[8] =    (   700 * lState.totalAirdrop) / 100_0000;
        lState.sizes[9] =    (   600 * lState.totalAirdrop) / 100_0000;
        lState.tires[8] = 4;
        lState.tires[9] = 4;
        
        lState.sizes[10] =   (   400 * lState.totalAirdrop) / 100_0000;
        lState.sizes[11] =   (   300 * lState.totalAirdrop) / 100_0000;
        lState.tires[10] = 5;
        lState.tires[11] = 5;
        
        lState.sizes[12] =   (   100 * lState.totalAirdrop) / 100_0000;
        lState.sizes[13] =   (    90 * lState.totalAirdrop) / 100_0000;
        lState.tires[12] = 6;
        lState.tires[13] = 6;
        
        lState.sizes[14] =   (    60 * lState.totalAirdrop) / 100_0000;
        lState.sizes[15] =   (    50 * lState.totalAirdrop) / 100_0000;
        lState.tires[14] = 7;
        lState.tires[15] = 7;
        
        lState.sizes[16] =   (    40 * lState.totalAirdrop) / 100_0000;
        lState.sizes[17] =   (    30 * lState.totalAirdrop) / 100_0000;
        lState.tires[16] = type(uint8).max;
        lState.tires[17] = type(uint8).max;

        lState.sizes[18] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];


        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);

            AccountState memory accountInfo = TokenContract.AccountData(lState.users[i]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();
        
            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(lState.tires[i], mintIndexTire, "user tire");
            if (lState.tires[i] != type(uint8).max)
                assertEq(0, mintIndexChunk, "user chunk");
            else
                assertEq(type(uint16).max, mintIndexChunk, "user chunk 2");

            //No shadows at first mint

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");

            
            if (lState.tires[i] != type(uint8).max) {
                console.log(" Tire contents");

                (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, lState.tires[i]);

                
                assertEq(1 + (i & 1), regularLength, "tire reg memb");
                assertEq(0, highLength, "tire high rewardmemb");
                assertEq(1, chunksCount, "tire chunks");


                console.log(" Chunk contents");
                (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, lState.tires[i], 0);

                
                assertEq(1 + (i & 1), chunkLen, "chunk length");
                assertEq(lState.users[i], chunkList[i & 1], "chunk list entry");
            }
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        {
            // Do not complete operation
            // to sanity check shadow index
            vm.startPrank(Owner);
            TokenContract.PrepareAirdrop(bytes32(uint256(1)), 1, 20_000);
            TokenContract.IndexShadow(20_000);
            vm.stopPrank();
        }


        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tire 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[14]); // -> moving to tire7
        vm.stopPrank();

        { //main
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User 0 tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(7, mintIndexTire, "user tire");
            assertEq(0, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 7);

            
            assertEq(3, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 7, 0);

            
            assertEq(3, chunkLen, "chunk length");
            assertEq(lState.users[0], chunkList[2], "chunk list entry");
        }
        { //shadow
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 shadowIndexTire = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert;
            uint16 shadowIndexChunk = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert;

            console.log("User 0 shadow tire: %d ; shadow chunk: %d", shadowIndexTire, shadowIndexChunk);

            assertEq(7, shadowIndexTire, "user shadow tire");
            assertEq(0, shadowIndexChunk, "user shadow chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex + 1, 7);

            
            assertEq(3, regularLength, "shadow tire reg memb");
            assertEq(0, highLength, "shadow tire high rewardmemb");
            assertEq(1, chunksCount, "shadow tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex + 1, 7, 0);

            
            assertEq(3, chunkLen, "shadow chunk length");
            assertEq(lState.users[0], chunkList[2], "shadow chunk list entry");
        }

        { //main
            AccountState memory accountInfo = TokenContract.AccountData(wasteWallet);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User waste tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(0, mintIndexTire, "user tire");
            assertEq(0, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 0);

            
            assertEq(2, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 0, 0);

            
            assertEq(2, chunkLen, "chunk length");
            assertEq(lState.users[1], chunkList[0], "chunk list entry 1");
            assertEq(wasteWallet, chunkList[1], "chunk list entry 2");
        }
        { //shadow
            AccountState memory accountInfo = TokenContract.AccountData(wasteWallet);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 shadowIndexTire = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert;
            uint16 shadowIndexChunk = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert;

            console.log("User waste shadow tire: %d ; shadow chunk: %d", shadowIndexTire, shadowIndexChunk);

            assertEq(0, shadowIndexTire, "user shadow tire");
            assertEq(0, shadowIndexChunk, "user shadow chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex + 1, 0);

            
            assertEq(1, regularLength, "shadow tire reg memb");
            assertEq(0, highLength, "shadow tire high rewardmemb");
            assertEq(1, chunksCount, "shadow tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex + 1, 0, 0);

            
            assertEq(1, chunkLen, "shadow chunk length");
            //assertEq(lState.users[1], chunkList[0], "shadow chunk list entry 1");
            assertEq(wasteWallet, chunkList[0], "shadow chunk list entry 2");
        }

        console.log("move outside tires");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[14] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        { //main
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User 0 tire: %d ; chunk: %d", mintIndexTire, mintIndexChunk);

            assertEq(type(uint8).max, mintIndexTire, "user tire");
            assertEq(type(uint16).max, mintIndexChunk, "user chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 7);

            
            assertEq(2, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 7, 0);

            
            assertEq(2, chunkLen, "chunk length");
            assertEq(lState.users[14], chunkList[0], "chunk list entry");
            assertEq(lState.users[15], chunkList[1], "chunk list entry");
        }
        { //shadow
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();


            uint8 shadowIndexTire = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert;
            uint16 shadowIndexChunk = ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert;

            console.log("User 0 shadow tire: %d ; shadow chunk: %d", shadowIndexTire, shadowIndexChunk);

            assertEq(type(uint8).max, shadowIndexTire, "user shadow tire");
            assertEq(type(uint16).max, shadowIndexChunk, "user shadow chunk");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex + 1, 7);

            
            assertEq(2, regularLength, "shadow tire reg memb");
            assertEq(0, highLength, "shadow tire high rewardmemb");
            assertEq(1, chunksCount, "shadow tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex + 1, 7, 0);

            
            assertEq(2, chunkLen, "shadow chunk length");
            assertEq(lState.users[13], chunkList[0], "chunk list entry");
            assertEq(lState.users[14], chunkList[1], "chunk list entry");
        }
    }



    struct _rewardDistroState {
        address[]  users;
        uint256[]  sizes;
        uint8[]    tires;
        uint256    totalAirdrop;
        bytes32    root;
        address    taxedWallet;

        MerkelTree tree;
    }


    function testTaxRewardDistro() public {
        _rewardDistroState memory lState;

        lState.users = new address[](5);
        lState.sizes = new uint256[](lState.users.length);
        lState.tires = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (2_0000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_9000 * lState.totalAirdrop) / 100_0000;
        lState.tires[0] = 0;
        lState.tires[1] = 0;

        lState.sizes[2] =    (  9000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.tires[2] = 1;
        lState.tires[3] = 1;


        lState.sizes[4] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[4] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];
        lState.taxedWallet = _allocateBurner();


        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        console.log();
        console.log("==================================================================");
        console.log("                           TRANSFERS");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            vm.startPrank(lState.users[i]);
            TokenContract.transfer(lState.taxedWallet, 100 * 1e18);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
        }

        _printWalletBalance(TaxAuth1);

        (, uint24 rewardMintIndex) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(1, rewardMintIndex, "reward mint index 1");

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        (, rewardMintIndex) = TokenContract.RewardCycles(TokenContract.CurrentRewardCycle());
        assertEq(1, rewardMintIndex, "reward mint index 2");

        console.log();
        console.log("==================================================================");
        console.log("                           REWARDED BALANCES");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            _printWalletBalance(lState.users[i]);
        }
    }

    
    function testAirdropLockedAvailable() public {
        address[] memory users = new address[](10);
        uint256[] memory sizes = new uint256[](users.length);
        uint256 totalAirdropSize = 0;

        for (uint256 i = 0; i < users.length; i++) {
            users[i] = _allocateBurner();
            sizes[i] = (i + 1) * 1e18;
            totalAirdropSize += (i + 1) * 1e18;
        }

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];

        console.log("Launching airdrop");

        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(root, totalAirdropSize, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();


        uint256 totalSupply1 = TokenContract.totalSupply();
        assertEq(totalAirdropSize, totalSupply1, "total supply1");
        console.log("Total supply: %d", totalSupply1);

        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        assertEq(totalAirdropSize, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "locked 1");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "available 1");


        console.log("Claiming");
        for (uint256 i = 2; i < users.length; i++) {
            bytes32[] memory proof = _extractMerkleProof(tree, i);

            vm.startPrank(users[i]);
            TokenContract.Airdrop(root, proof, sizes[i]);
            vm.stopPrank();
        }

        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        assertEq(sizes[0] + sizes[1], TokenContract.balanceOf(TokenContract.LockedMintAddress()), "locked 2");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "available 2");

        
        console.log("Stopping");
        vm.startPrank(Owner);
        TokenContract.StopAirdrop(root);
        vm.stopPrank();

        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        assertEq(0, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "locked 3");
        assertEq(sizes[0] + sizes[1], TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "available 3");


        console.log("NewAirdrop");

        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(bytes32(uint256(0x1234567890)), sizes[0] + sizes[1] + 1, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        
        uint256 totalSupply2 = TokenContract.totalSupply();
        console.log("Total supply: %d", totalSupply2);
        assertEq(totalSupply1 + 1, totalSupply2, "total supply 2");

        _printWalletBalance(TokenContract.LockedMintAddress());
        _printWalletBalance(TokenContract.AvailableMintAddress());

        assertEq(sizes[0] + sizes[1] + 1, TokenContract.balanceOf(TokenContract.LockedMintAddress()), "locked 4");
        assertEq(0, TokenContract.balanceOf(TokenContract.AvailableMintAddress()), "available 4");
    }


    function testTaxRewardDistroHighMembers() public {
        _rewardDistroState memory lState;

        lState.users = new address[](5);
        lState.sizes = new uint256[](lState.users.length);
        lState.tires = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (2_0000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_9000 * lState.totalAirdrop) / 100_0000;
        lState.tires[0] = 0;
        lState.tires[1] = 0;

        lState.sizes[2] =    (  9000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  8000 * lState.totalAirdrop) / 100_0000;
        lState.tires[2] = 1;
        lState.tires[3] = 1;


        lState.sizes[4] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[4] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];
        lState.taxedWallet = _allocateBurner();


        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(lState.taxedWallet, true);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
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
            TokenContract.transfer(lState.taxedWallet, 100 * 1e18);
            vm.stopPrank();

            _printWalletBalance(lState.users[i]);
        }

        _printWalletBalance(TaxAuth1);

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle();
        vm.stopPrank();

        console.log();
        console.log("==================================================================");
        console.log("                           REWARDED BALANCES");
        console.log();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            _printWalletBalance(lState.users[i]);
        }
    }

    function testChunkListLogic() public {
        for (uint256 i = 0; i < 60; i++) {
            TokenContract.DebugAppendAccountToMintIndex(1010, 1, address(uint160(i+1)));
        }

        {
            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(60, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(3, chunksCount, "tire chunks");

            console.log(" Chunk contents");

            uint256 lastVisitedAddress = 0;

            for (uint256 chunk = 0; chunk < chunksCount; chunk++) {
                (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(1010, 1, chunk);

                assertEq(CHUNK_SIZE, chunkLen, "chunk length");

                for (uint256 i = 0; i < chunkLen; i++) {
                    lastVisitedAddress = chunk * CHUNK_SIZE + i + 1;

                    assertEq(lastVisitedAddress, uint160(chunkList[i]), "chunk list entry 1");
                }
            }

            assertEq(60, lastVisitedAddress, "last visited adress");
        }

        console.log("Dropping records");
        {
            TokenContract.DebugDropAccountFromMintIndex(1010, address(25), 1, 1);

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(59, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(3, chunksCount, "tire chunks");

            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(1010, 1, 1);

            assertEq(CHUNK_SIZE - 1, chunkLen, "chunk length");
            assertEq(40, uint160(chunkList[4]), "chunk list entry 2");

            console.log(" wrong entry");
            vm.expectRevert(bytes("Nothing has been deleted"));
            TokenContract.DebugDropAccountFromMintIndex(1010, address(1000000), 1, 1);

            console.log(" wrong chunk");
            vm.expectRevert(bytes("wrong chunk"));
            TokenContract.DebugDropAccountFromMintIndex(1010, address(1000000), 1, 555555);


            console.log("Drop from end");
            TokenContract.DebugDropAccountFromMintIndex(1010, address(41), 1, 2);

            (regularLength, highLength, chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(58, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(3, chunksCount, "tire chunks");

            console.log(" Chunk contents");
            (chunkLen, chunkList) = TokenContract.GetTireChunk(1010, 1, 2);

            assertEq(CHUNK_SIZE - 1, chunkLen, "chunk length");
            assertEq(60, uint160(chunkList[0]), "chunk list entry 3");
        }

        console.log("add 1 record");

        {
            TokenContract.DebugAppendAccountToMintIndex(1010, 1, address(61));

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(59, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(3, chunksCount, "tire chunks");

            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(1010, 1, 2);

            assertEq(CHUNK_SIZE, chunkLen, "chunk length");
            assertEq(61, uint160(chunkList[chunkLen - 1]), "chunk list entry 3");
        }

        console.log("add yet 1 record");
        
        {
            TokenContract.DebugAppendAccountToMintIndex(1010, 1, address(62));

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(60, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(4, chunksCount, "tire chunks");

            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(1010, 1, 3);

            assertEq(1, chunkLen, "chunk length");
            assertEq(62, uint160(chunkList[0]), "chunk list entry 4");
        }

    }

    function testChunkListLogicBoosted() public {
        for (uint256 i = 4; i < 10; i++) {
            vm.startPrank(Owner);
            TokenContract.DebugBoostWalletCore(address(uint160(i + 1)));
            vm.stopPrank();
        }

        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(Owner);
            TokenContract.DebugAppendAccountToMintIndex(1010, 1, address(uint160(i + 1)));
            vm.stopPrank();
        }

        {
            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(1010, 1);

            
            assertEq(4, regularLength, "tire reg memb");
            assertEq(6, highLength, "tire high rewardmemb");
            assertEq(1, chunksCount, "tire chunks");

            console.log(" Chunk contents");

            uint256 lastVisitedAddress = 0;

            for (uint256 chunk = 0; chunk < chunksCount; chunk++) {
                (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(1010, 1, chunk);

                assertEq(10, chunkLen, "chunk length");

                for (uint256 i = 0; i < chunkLen; i++) {
                    lastVisitedAddress = chunk * CHUNK_SIZE + i + 1;

                    assertEq(lastVisitedAddress, uint160(chunkList[i]), "chunk list entry 1");
                }
            }

            assertEq(10, lastVisitedAddress, "last visited adress");
        }
    }

    function testDoubleActionLaunchAirdrop() public {
        console.log("Preparing Airdrop");

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

        

        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(root, totalAirdropSize, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();

        TokenContract.StopAirdrop(root);
        vm.stopPrank();

        console.log("Trying launch 2nd time");
        
        vm.startPrank(Owner);
        vm.expectRevert(bytes("This airdrop has already been registred"));
        TokenContract.PrepareAirdrop(root, totalAirdropSize, 20_000);
        vm.stopPrank();
    }

    function testDoubleActionClaimAirdrop() public {
        console.log("Preparing Airdrop");

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

        

        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(root, totalAirdropSize, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        console.log("Claiming Airdrop");

        bytes32[] memory proof = _extractMerkleProof(tree, 0);

        vm.startPrank(users[0]);
        TokenContract.Airdrop(root, proof, sizes[0]);
        vm.stopPrank();

        console.log("Claiming Airdrop 2nd tiime");

        vm.startPrank(users[0]);
        vm.expectRevert(bytes("Already claimed"));
        TokenContract.Airdrop(root, proof, sizes[0]);
        vm.stopPrank();
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

        console.log("PrepareAirdrop");
        vm.expectRevert(revertExptMsg);
        TokenContract.PrepareAirdrop(bytes32(uint256(1)), 1, 1);

        console.log("IndexShadow");
        vm.expectRevert(revertExptMsg);
        TokenContract.IndexShadow(1);

        console.log("LaunchAirdrop");
        vm.expectRevert(revertExptMsg);
        TokenContract.LaunchAirdrop();

        console.log("StopAirdrop");
        vm.expectRevert(revertExptMsg);
        TokenContract.StopAirdrop(bytes32(uint256(2)));

        console.log("MintTo");
        vm.expectRevert(revertExptMsg);
        TokenContract.MintTo(address(1));




        console.log("LaunchNewRewardCycle");
        vm.expectRevert(revertExptMsg);
        TokenContract.LaunchNewRewardCycle();

        console.log("SetTaxRatio");
        vm.expectRevert(revertExptMsg);
        TokenContract.SetTaxRatio(1,1);

        console.log("UpdateTaxAuthorities");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateTaxAuthorities(address(1), address(1));

        console.log("UpdateWhitelisting");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateWhitelisting(address(1), true);

        console.log("EnableReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.StopAirdrop(bytes32(uint256(2)));

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

        vm.stopPrank();
    }

    function testShadowIndexiengBigBase() public {
        console.log("Preparing airdrop");
        _airDropTireingState memory lState;

        lState.users = new address[](601);
        lState.sizes = new uint256[](lState.users.length);

        lState.totalAirdrop = 10_000_000 * 1e18;

        for (uint256 i = 0; i < 300; i++) {
            //Tier 3
            lState.users[i] = _allocateBurner();
            lState.sizes[i] = (900 * lState.totalAirdrop) / 100_0000;
        }

        for (uint256 i = 300; i < (lState.users.length - 1); i++) {
            //Tier 4

            lState.users[i] = _allocateBurner();
            lState.sizes[i] = (600 * lState.totalAirdrop) / 100_0000;
        }

        
        lState.users[600] = _allocateBurner();        
        lState.sizes[600] = lState.totalAirdrop;

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[600] -= lState.sizes[i];
        }

        lState.tree = _generateAirdropMerkleTree(lState.users, lState.sizes);
        lState.root = lState.tree.flatTree[lState.tree.flatTree.length - 1];

        

        console.log("Launching airdrop");
        vm.startPrank(Owner);
        TokenContract.PrepareAirdrop(lState.root, lState.totalAirdrop, 20_000);
        TokenContract.IndexShadow(20_000);
        TokenContract.LaunchAirdrop();
        vm.stopPrank();

        console.log("Claiming airdrop");
        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            bytes32[] memory proof = _extractMerkleProof(lState.tree, i);

            vm.startPrank(lState.users[i]);
            TokenContract.Airdrop(lState.root, proof, lState.sizes[i]);
            vm.stopPrank();
        }


        console.log("Launching new airdrop - turning on shadow indexing");
        vm.startPrank(Owner);        
        TokenContract.PrepareAirdrop(bytes32(uint256(1)), 1, gasleft());
        vm.stopPrank();

        console.log("validating initial state");
        assertEq(0, TokenContract.LastShadowIndexedTire());
        assertEq(0, TokenContract.LastShadowIndexedChunk());

        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[CHUNK_SIZE]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("User %d tire: %d ; chunk: %d", CHUNK_SIZE, mintIndexTire, mintIndexChunk);

            assertEq(3, mintIndexTire, "user tire");
            assertEq(1, mintIndexChunk, "user chunk");

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");

            console.log(" Tire contents");

            (uint32 regularLength, uint32 highLength, uint32 chunksCount) = TokenContract.GetTireData(currentMintIndex, 3);

            
            assertEq(300, regularLength, "tire reg memb");
            assertEq(0, highLength, "tire high rewardmemb");
            assertEq(15, chunksCount, "tire chunks");


            console.log(" Chunk contents");
            (uint8 chunkLen, address[CHUNK_SIZE] memory chunkList) = TokenContract.GetTireChunk(currentMintIndex, 3, 1);

            
            assertEq(CHUNK_SIZE, chunkLen, "chunk length");
            assertEq(lState.users[CHUNK_SIZE], chunkList[0], "chunk list entry");
        }

        uint256 newLowTireThreshold = (600 * (lState.totalAirdrop + 1)) / 100_0000;
        address wasteWallet = _allocateBurner();

        console.log("transfers on empty shadow index");
        //low tiering in main, but remain on low tire in shadow
        //1 from first chunk
        //1 from second

        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - newLowTireThreshold);
        vm.stopPrank();

        vm.startPrank(lState.users[CHUNK_SIZE]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - newLowTireThreshold);
        vm.stopPrank();
        console.log("  validating first user sahdow");
        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[0]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("  User %d tire: %d ; chunk: %d", 0, mintIndexTire, mintIndexChunk);

            assertEq(4, mintIndexTire, "user tire");
            assertEq(15, mintIndexChunk, "user chunk");

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");
        }
        console.log("  validating second user sahdow");
        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[CHUNK_SIZE]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("  User %d tire: %d ; chunk: %d", CHUNK_SIZE, mintIndexTire, mintIndexChunk);

            assertEq(4, mintIndexTire, "user tire");
            assertEq(15, mintIndexChunk, "user chunk");

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");
        }


        console.log("do first index iteration");
        {
            vm.startPrank(Owner);
            uint256 gas1 = gasleft();
            TokenContract.IndexShadow{gas: 10_000_000} (10_000_000 - 1_000_000);
            uint256 gas2 = gasleft();
            vm.stopPrank();

            console.log("check sanity");

            console.log("gas spent: %d", gas1 - gas2);
            console.log("Last indexed tire:%d", TokenContract.LastShadowIndexedTire());
            console.log("Last indexed chunk:%d", TokenContract.LastShadowIndexedChunk());

            assertEq(3, TokenContract.LastShadowIndexedTire());
            assertEq(1, TokenContract.LastShadowIndexedChunk());
        }



        console.log("check transfer influence");
        //low tiering in main, but remain on low tire in shadow
        //1 from first chunk
        //1 from second

        vm.startPrank(lState.users[1]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - newLowTireThreshold - 1);
        vm.stopPrank();

        vm.startPrank(lState.users[CHUNK_SIZE + 1]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - newLowTireThreshold - 1);
        vm.stopPrank();
        console.log("  validating first user sahdow");
        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[1]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("  User %d tire: %d ; chunk: %d", 1, mintIndexTire, mintIndexChunk);

            assertEq(4, mintIndexTire, "user tire");
            assertEq(15, mintIndexChunk, "user chunk");

            assertEq(4, ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, ~accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(currentMintIndex + 1, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");
        }
        console.log("  validating second user sahdow");
        {
            AccountState memory accountInfo = TokenContract.AccountData(lState.users[CHUNK_SIZE + 1]);
            uint256 currentMintIndex = TokenContract.ActiveMintIndex();

            uint8 mintIndexTire = ~accountInfo.tirePoitnters[currentMintIndex % 2].tireIdInvert;
            uint16 mintIndexChunk = ~accountInfo.tirePoitnters[currentMintIndex % 2].chunkIdInvert;

            console.log("  User %d tire: %d ; chunk: %d", CHUNK_SIZE + 1, mintIndexTire, mintIndexChunk);

            assertEq(4, mintIndexTire, "user tire");
            assertEq(15, mintIndexChunk, "user chunk");

            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].tireIdInvert, "shadow index tire");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].chunkIdInvert, "shadow index chunk");
            assertEq(0, accountInfo.tirePoitnters[(currentMintIndex + 1) % 2].indexId, "shadow index id");
        }
        
    }

    //TODO: Tests with multiple shadow index iteraions

}