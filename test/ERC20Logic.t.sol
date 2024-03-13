// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ReflectDebug} from "../src/ReflectErc20Debug.sol";
import "../src/ReflectDataModel.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


bytes16 constant HEX_DIGITS = "0123456789abcdef";

contract ERC20Logic is Test {
        
    ReflectDebug                            public              TokenContract;

    address                                 public              RewardWallet;
    address                                 public              TeamWallet        = address(uint160(0xAAAA003A602));
    address                                 public              Owner             = address(uint160(0xAABBCC0000));
    address                                 public              NextUserBurner    = address(uint160(0xCC00220000));
    address                                 public              FundWallet        = address(uint160(0xBBB0000FFFF));


    function setUp() public {
        vm.startPrank(Owner);
        TokenContract = new ReflectDebug(TeamWallet, 10_000_000_000 ether);
        vm.stopPrank();

        RewardWallet = address(TokenContract);

        console.log("                     $REFLECT: %s", address(TokenContract));
        
        vm.startPrank(Owner);
        TokenContract.ExcludeWalletFromRewards(FundWallet);
        TokenContract.transferFrom(address(TokenContract), FundWallet, 10_000_000_000 ether);
        vm.stopPrank();
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

    
    function testTaxCollectionHigh() public {
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
        _printWalletBalance(address(TokenContract));

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 90_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");

        uint256 taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq( 10_0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(address(TokenContract));

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(180_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");

        taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq( 20_0 * 1e18, taxed, "rew cycle taxed 2");

        
        console.log("Tax on from");
        
        address wasteWallet = _allocateBurner();
        vm.startPrank(taxable);
        TokenContract.transfer(wasteWallet, 100_0 * 1e18);
        vm.stopPrank();

        
        _printWalletBalance(taxable);
        _printWalletBalance(wasteWallet);
        _printWalletBalance(address(TokenContract));

        assertEq( 80_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 3");
        assertEq( 90_0 * 1e18, TokenContract.balanceOf(wasteWallet), "waste balance");
        
        taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq( 30_0 * 1e18, taxed, "rew cycle taxed 3");
    }

    function testTaxCollectionLow() public {
        address taxable = _allocateBurner();

        address user1 = _allocateBurner();
        address user2 = _allocateBurner();

        vm.startPrank(Owner);
        TokenContract.UpdateWhitelisting(taxable, true);

        TokenContract.SetRegularTaxBlock(block.number - 1);
        vm.stopPrank();


        _fundWallet(user1, 200_0 * 1e18);
        _fundWallet(user2, 200_0 * 1e18);

        console.log("First transfer");

        vm.startPrank(user1);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();

        _printWalletBalance(user1);
        _printWalletBalance(taxable);
        _printWalletBalance(address(TokenContract));

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user1), "user1 balance");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 1");

        uint256 taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq(  5_0 * 1e18, taxed, "rew cycle taxed 1");

        console.log("Second transfer");
        
        vm.startPrank(user2);
        TokenContract.transfer(taxable, 100_0 * 1e18);
        vm.stopPrank();
        
        _printWalletBalance(user2);
        _printWalletBalance(taxable);
        _printWalletBalance(address(TokenContract));

        assertEq(100_0 * 1e18, TokenContract.balanceOf(user2), "user2 balance");
        assertEq(190_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 2");

        taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq( 10_0 * 1e18, taxed, "rew cycle taxed 2");

        
        console.log("Tax on from");
        
        address wasteWallet = _allocateBurner();
        vm.startPrank(taxable);
        TokenContract.transfer(wasteWallet, 100_0 * 1e18);
        vm.stopPrank();

        
        _printWalletBalance(taxable);
        _printWalletBalance(wasteWallet);
        _printWalletBalance(address(TokenContract));

        assertEq( 90_0 * 1e18, TokenContract.balanceOf(taxable), "taxable balance 3");
        assertEq( 95_0 * 1e18, TokenContract.balanceOf(wasteWallet), "waste balance");
        
        taxed = TokenContract.balanceOf(address(TokenContract));
        assertEq( 15_0 * 1e18, taxed, "rew cycle taxed 3");
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

    struct _airDropTieringState {
        address[]  users;
        uint256[]  sizes;
        uint8[]    tiers;
        uint256    totalAirdrop;
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
                (uint256 regMemmbers, uint256 boostedMembers) = 
                    TokenContract.GetRewardCycleTierStat(lState.tiers[i]);

                console.log("Tier %d stat: regular: %d, boosted: %d", lState.tiers[i], regMemmbers, boostedMembers);
                assertEq(1 + (i & 1), regMemmbers, "reg Membs");
                assertEq(0, boostedMembers, "bst Membs");

                (uint256 tire, bool boosted, bool found) = 
                    TokenContract.GetWalletRewardTier(lState.users[i]);
                
                console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                assertEq(lState.tiers[i], tire, "Wallet tier");
                assertEq(false, boosted, "Boosted wallet");
                assertEq(true, found, "Wallet tier found");
            } else {
                (uint256 tire, bool boosted, bool found) = 
                    TokenContract.GetWalletRewardTier(lState.users[i]);
                
                console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                assertEq(type(uint256).max, tire, "Wallet tier");
                assertEq(false, boosted, "Boosted wallet");
                assertEq(false, found, "Wallet tier found");
            }


            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tier 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[15]); // -> moving to tier7
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(3, regMemmbers, "reg Membs 2");
            assertEq(0, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(7, tire, "Wallet tier");
            assertEq(false, boosted, "Boosted wallet");
            assertEq(true, found, "Wallet tier found");
        }

        console.log("move outside tiers");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[15] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs 2");
            assertEq(0, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(type(uint256).max, tire, "Wallet tier");
            assertEq(false, boosted, "Boosted wallet");
            assertEq(false, found, "Wallet tier found");
        }
    }

    //V1 boost after distribution
    //V2 boost before distribution

    function testTransferRetieringWithBoostedV1() public {
        _airDropTieringState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tiers = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        { //account balances & tiers
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

        }

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }


        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);

            if (lState.tiers[i] != type(uint8).max) {
                (uint256 regMemmbers, uint256 boostedMembers) = 
                    TokenContract.GetRewardCycleTierStat(lState.tiers[i]);

                console.log("Tier %d stat: regular: %d, boosted: %d", lState.tiers[i], regMemmbers, boostedMembers);
                assertEq(1 + (i & 1), regMemmbers, "reg Membs");
                assertEq(0, boostedMembers, "bst Membs");

                (uint256 tire, bool boosted, bool found) = 
                    TokenContract.GetWalletRewardTier(lState.users[i]);
                
                console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                assertEq(lState.tiers[i], tire, "Wallet tier");
                assertEq(false, boosted, "Boosted wallet");
                assertEq(true, found, "Wallet tier found");
            } else {
                (uint256 tire, bool boosted, bool found) = 
                    TokenContract.GetWalletRewardTier(lState.users[i]);
                
                console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                assertEq(type(uint256).max, tire, "Wallet tier");
                assertEq(false, boosted, "Boosted wallet");
                assertEq(false, found, "Wallet tier found");
            }


            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[0]);
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(1, regMemmbers, "reg Membs");
            assertEq(1, boostedMembers, "bst Membs");

            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(0, tire, "Wallet tier");
            assertEq(true, boosted, "Boosted wallet");
            assertEq(true, found, "Wallet tier found");
        }

        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tier 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[15]); // -> moving to tier7
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs 2");
            assertEq(1, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(7, tire, "Wallet tier");
            assertEq(true, boosted, "Boosted wallet");
            assertEq(true, found, "Wallet tier found");
        }

        console.log("move outside tiers");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[15] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs 2");
            assertEq(0, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(type(uint256).max, tire, "Wallet tier");
            assertEq(false, boosted, "Boosted wallet");
            assertEq(false, found, "Wallet tier found");
        }
    }



    function testTransferRetieringWithBoostedV2() public {
        _airDropTieringState memory lState;

        lState.users = new address[](19);
        lState.sizes = new uint256[](lState.users.length);
        lState.tiers = new uint8[](lState.users.length - 1);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        { //account balances & tiers
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

        }

        for (uint256 i = 0; i < (lState.sizes.length - 1); i++) {
            lState.sizes[18] -= lState.sizes[i];
        }

        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[0]);
        vm.stopPrank();

        for (uint256 i = 0; i < (lState.users.length - 1); i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);

            if (lState.tiers[i] != type(uint8).max) {
                if (i > 1) { //on low tiers as usual
                    (uint256 regMemmbers, uint256 boostedMembers) = 
                        TokenContract.GetRewardCycleTierStat(lState.tiers[i]);

                    console.log("Tier %d stat: regular: %d, boosted: %d", lState.tiers[i], regMemmbers, boostedMembers);
                    assertEq(1 + (i & 1), regMemmbers, "reg Membs");
                    assertEq(0, boostedMembers, "bst Membs");

                    (uint256 tire, bool boosted, bool found) = 
                        TokenContract.GetWalletRewardTier(lState.users[i]);
                    
                    console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                    assertEq(lState.tiers[i], tire, "Wallet tier");
                    assertEq(false, boosted, "Boosted wallet");
                    assertEq(true, found, "Wallet tier found");
                } else { //but on tier 0 diff behavior
                    (uint256 regMemmbers, uint256 boostedMembers) = 
                        TokenContract.GetRewardCycleTierStat(lState.tiers[i]);

                    console.log("Tier %d stat: regular: %d, boosted: %d", lState.tiers[i], regMemmbers, boostedMembers);
                    assertEq(i & 1, regMemmbers, "reg Membs");
                    assertEq(1, boostedMembers, "bst Membs");

                    (uint256 tire, bool boosted, bool found) = 
                        TokenContract.GetWalletRewardTier(lState.users[i]);
                    
                    console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                    assertEq(lState.tiers[i], tire, "Wallet tier");
                    assertEq(i == 0, boosted, "Boosted wallet");
                    assertEq(true, found, "Wallet tier found");
                }
                
            } else {
                (uint256 tire, bool boosted, bool found) = 
                    TokenContract.GetWalletRewardTier(lState.users[i]);
                
                console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

                assertEq(type(uint256).max, tire, "Wallet tier");
                assertEq(false, boosted, "Boosted wallet");
                assertEq(false, found, "Wallet tier found");
            }


            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }


        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(1, regMemmbers, "reg Membs");
            assertEq(1, boostedMembers, "bst Membs");

            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(0, tire, "Wallet tier");
            assertEq(true, boosted, "Boosted wallet");
            assertEq(true, found, "Wallet tier found");
        }

        address wasteWallet = _allocateBurner();
        
        console.log("Transfer some tokens & test reteiring. 1st move to tier 7");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[0] - lState.sizes[15]); // -> moving to tier7
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs 2");
            assertEq(1, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(7, tire, "Wallet tier");
            assertEq(true, boosted, "Boosted wallet");
            assertEq(true, found, "Wallet tier found");
        }

        console.log("move outside tiers");
        vm.startPrank(lState.users[0]);
        TokenContract.transfer(wasteWallet, lState.sizes[15] - lState.sizes[16]); // -> moving out from index
        vm.stopPrank();

        {
            (uint256 regMemmbers, uint256 boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(0);

            console.log("Tier 0 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs");
            assertEq(0, boostedMembers, "bst Membs");

            (regMemmbers, boostedMembers) = 
                TokenContract.GetRewardCycleTierStat(7);
            console.log("Tier 7 stat: regular: %d, boosted: %d", regMemmbers, boostedMembers);
            assertEq(2, regMemmbers, "reg Membs 2");
            assertEq(0, boostedMembers, "bst Membs 2");


            (uint256 tire, bool boosted, bool found) = 
                TokenContract.GetWalletRewardTier(lState.users[0]);
            
            console.log("Wallet tier %d; boosted: %s; found: %s", tire, boosted, found);

            assertEq(type(uint256).max, tire, "Wallet tier");
            assertEq(false, boosted, "Boosted wallet");
            assertEq(false, found, "Wallet tier found");
        }
    }




    
    function testOwnerAccess() public {
        vm.startPrank(address(0xface00add));

        bytes memory revertExptMsg = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0xface00add));


        console.log("DistributeReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.DistributeReward(new address[](0), new uint256[](0), 1);

        console.log("EnableReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.EnableReward(bytes32(uint256(2)));

        console.log("DisableReward");
        vm.expectRevert(revertExptMsg);
        TokenContract.DisableReward(bytes32(uint256(2)));


        console.log("LaunchUniV2Pool");
        vm.expectRevert(revertExptMsg);
        TokenContract.LaunchUniV2Pool(1);

        console.log("LaunchNewRewardCycle");
        vm.expectRevert(revertExptMsg);
        TokenContract.LaunchNewRewardCycle(0, false);

        
        console.log("FixEthRewards");
        vm.expectRevert(revertExptMsg);
        TokenContract.FixEthRewards(1);



        console.log("UpdateTeamWallet");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateTeamWallet(address(1));

        console.log("UpdateWhitelisting");
        vm.expectRevert(revertExptMsg);
        TokenContract.UpdateWhitelisting(address(1), true);

        console.log("BoostWallet");
        vm.expectRevert(revertExptMsg);
        TokenContract.BoostWallet(address(1));


        console.log("ExcludeWalletFromRewards");
        vm.expectRevert(revertExptMsg);
        TokenContract.ExcludeWalletFromRewards(address(1));
        

        vm.stopPrank();
    }
}