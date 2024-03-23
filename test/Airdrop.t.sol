// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ReflectErc20OnMainnet} from "../src/ReflectErc20OnMainnet.sol";
import "../src/ReflectDataModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";


bytes16 constant HEX_DIGITS = "0123456789abcdef";

contract Airdrop is Test {
    ReflectErc20OnMainnet                   public              TokenContract;

    address                                 public              RewardWallet;
    address                                 public              TeamWallet        = address(uint160(0xAAAA003A602));
    address                                 public              Owner             = address(uint160(0xAABBCC0000));
    address                                 public              NextUserBurner    = address(uint160(0xCC00220000));
    IERC20                                  public immutable    wETH              = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);


    function setUp() public {
        vm.createSelectFork("ethereum");

        vm.startPrank(Owner);
        TokenContract = new ReflectErc20OnMainnet(TeamWallet, 200 ether, 110 ether);
        vm.stopPrank();

        RewardWallet = address(TokenContract);

        console.log("                     $REFLECT: %s", address(TokenContract));
        console.log("               UNI V2 FACTORY: %s", address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f));
        console.log("                         wETH: %s", address(wETH));
        
        assertEq(110 ether, TokenContract.AirdropSupply(), "Wrong AirdropSupply");
        assertEq(200 ether, TokenContract.totalSupply(), "totalSupply");
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

    function testAirdropWithSale() public {
        address[] memory users = new address[](3);
        uint256[] memory sizes = new uint256[](3);

        users[0] = _allocateBurner();
        sizes[0] = 10 ether;

        users[1] = _allocateBurner();
        sizes[1] = 40 ether;

        users[2] = _allocateBurner();
        sizes[2] = 60 ether;

        
        uint256 airdropSize = 0;

        for (uint256 i = 0; i < sizes.length; i++) {
            airdropSize += sizes[i];
        }

        assertEq(TokenContract.AirdropSupply(), airdropSize, "Wrong airdrop size, adjust vars");
    

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];

        
        assertEq(bytes32(0), TokenContract.AirdropRoot(), "init root");

        vm.startPrank(Owner);
        TokenContract.SetAirdropRoot(root);
        vm.stopPrank();

        assertEq(root, TokenContract.AirdropRoot(), "new root");

        for (uint256 i = 0; i < users.length; i++) {
            bytes32[] memory proof = _extractMerkleProof(tree, i);

            _printWalletBalance(users[i]);
            assertEq(0, TokenContract.balanceOf(users[i]), "balance before airdrop");

            vm.startPrank(users[i]);
            TokenContract.Airdrop(root, proof, sizes[i]);
            vm.stopPrank();

            _printWalletBalance(users[i]);
            assertEq(sizes[i], TokenContract.balanceOf(users[i]), "balance after airdrop");
        }


        console.log("Creating Uniswap V2 pair");

        deal(address(wETH), address(TokenContract), 1_000_000 ether);

        vm.startPrank(Owner);
        IUniswapV2Pair pair = IUniswapV2Pair(TokenContract.LaunchUniV2Pool(10));
        vm.stopPrank();

        assertEq(90 ether, TokenContract.balanceOf(address(pair)), "Pair balance");
        assertEq(TokenContract.totalSupply(), airdropSize + TokenContract.balanceOf(address(pair)), "total supply checksum");
    }

    
    function testAirdropOverflow() public {
        address[] memory users = new address[](3);
        uint256[] memory sizes = new uint256[](3);

        users[0] = _allocateBurner();
        sizes[0] = 10 ether;

        users[1] = _allocateBurner();
        sizes[1] = 40 ether;

        users[2] = _allocateBurner();
        sizes[2] = 100 ether;

        
        uint256 airdropSize = 0;

        for (uint256 i = 0; i < sizes.length; i++) {
            airdropSize += sizes[i];
        }

        assertLt(TokenContract.AirdropSupply(), airdropSize, "Wrong airdrop size, adjust vars");
    

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];

        
        assertEq(bytes32(0), TokenContract.AirdropRoot(), "init root");

        vm.startPrank(Owner);
        TokenContract.SetAirdropRoot(root);
        vm.stopPrank();

        assertEq(root, TokenContract.AirdropRoot(), "new root");

        for (uint256 i = 0; i < users.length - 1; i++) {
            bytes32[] memory proof = _extractMerkleProof(tree, i);

            _printWalletBalance(users[i]);
            assertEq(0, TokenContract.balanceOf(users[i]), "balance before airdrop");

            vm.startPrank(users[i]);
            TokenContract.Airdrop(root, proof, sizes[i]);
            vm.stopPrank();

            _printWalletBalance(users[i]);
            assertEq(sizes[i], TokenContract.balanceOf(users[i]), "balance after airdrop");
        }


        {
            bytes32[] memory proof = _extractMerkleProof(tree, 2);

            _printWalletBalance(users[2]);
            assertEq(0, TokenContract.balanceOf(users[2]), "balance before airdrop");

            vm.startPrank(users[2]);
            vm.expectRevert(bytes("Supply overflow"));
            TokenContract.Airdrop(root, proof, sizes[2]);
            vm.stopPrank();

            _printWalletBalance(users[2]);
            assertEq(0, TokenContract.balanceOf(users[2]), "balance after airdrop");
        }
    }

    function testAirdropWrongRoot() public {
        address[] memory users = new address[](3);
        uint256[] memory sizes = new uint256[](3);

        users[0] = _allocateBurner();
        sizes[0] = 10 ether;

        users[1] = _allocateBurner();
        sizes[1] = 40 ether;

        users[2] = _allocateBurner();
        sizes[2] = 100 ether;

        
        uint256 airdropSize = 0;

        for (uint256 i = 0; i < sizes.length; i++) {
            airdropSize += sizes[i];
        }

        assertLt(TokenContract.AirdropSupply(), airdropSize, "Wrong airdrop size, adjust vars");
    

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];

        
        assertEq(bytes32(0), TokenContract.AirdropRoot(), "init root");

        {
            bytes32[] memory proof = _extractMerkleProof(tree, 2);

            _printWalletBalance(users[0]);
            assertEq(0, TokenContract.balanceOf(users[0]), "balance before airdrop");

            vm.startPrank(users[0]);
            vm.expectRevert(bytes("Unrecognized airdrop"));
            TokenContract.Airdrop(root, proof, sizes[0]);
            vm.stopPrank();

            _printWalletBalance(users[0]);
            assertEq(0, TokenContract.balanceOf(users[0]), "balance after airdrop");
        }
    }

    
    function testAirdropWrongLeaf() public {
        address[] memory users = new address[](3);
        uint256[] memory sizes = new uint256[](3);


        users[0] = _allocateBurner();
        sizes[0] = 10 ether;

        users[1] = _allocateBurner();
        sizes[1] = 40 ether;

        users[2] = _allocateBurner();
        sizes[2] = 100 ether;

        
        uint256 airdropSize = 0;

        for (uint256 i = 0; i < sizes.length; i++) {
            airdropSize += sizes[i];
        }

        assertLt(TokenContract.AirdropSupply(), airdropSize, "Wrong airdrop size, adjust vars");

        MerkelTree memory tree = _generateAirdropMerkleTree(users, sizes);
        bytes32 root = tree.flatTree[tree.flatTree.length - 1];
        
        assertEq(bytes32(0), TokenContract.AirdropRoot(), "init root");

        vm.startPrank(Owner);
        TokenContract.SetAirdropRoot(root);
        vm.stopPrank();

        assertEq(root, TokenContract.AirdropRoot(), "new root");

        address fakeUSer = _allocateBurner();

        {
            bytes32[] memory proof = _extractMerkleProof(tree, 2);

            _printWalletBalance(fakeUSer);
            assertEq(0, TokenContract.balanceOf(fakeUSer), "balance before airdrop");

            vm.startPrank(fakeUSer);
            vm.expectRevert(bytes("You're not part of this airdrop or input is wrong"));
            TokenContract.Airdrop(root, proof, sizes[0]);
            vm.stopPrank();

            _printWalletBalance(fakeUSer);
            assertEq(0, TokenContract.balanceOf(fakeUSer), "balance after airdrop");
        }

        {
            bytes32[] memory proof = _extractMerkleProof(tree, 2);

            _printWalletBalance(users[1]);
            assertEq(0, TokenContract.balanceOf(users[1]), "balance before airdrop");

            vm.startPrank(users[1]);
            vm.expectRevert(bytes("You're not part of this airdrop or input is wrong"));
            TokenContract.Airdrop(root, proof, 40 ether);
            vm.stopPrank();

            _printWalletBalance(users[1]);
            assertEq(0, TokenContract.balanceOf(users[1]), "balance after airdrop");
        }
    }

}