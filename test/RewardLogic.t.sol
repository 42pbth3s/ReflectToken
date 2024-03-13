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

contract RewardLogic is Test {
        
    ReflectErc20OnMainnet                   public              TokenContract;

    address                                 public              RewardWallet;
    address                                 public              TeamWallet        = address(uint160(0xAAAA003A602));
    address                                 public              Owner             = address(uint160(0xAABBCC0000));
    address                                 public              NextUserBurner    = address(uint160(0xCC00220000));
    address                                 public              FundWallet        = address(uint160(0xBBB0000FFFF));
    IERC20                                  public immutable    wETH              = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);


    function setUp() public {
        vm.createSelectFork("ethereum");

        vm.startPrank(Owner);
        TokenContract = new ReflectErc20OnMainnet(TeamWallet, 10_000_000_000 ether);
        vm.stopPrank();

        RewardWallet = address(TokenContract);

        console.log("                     $REFLECT: %s", address(TokenContract));
        console.log("               UNI V2 FACTORY: %s", address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f));
        console.log("                         wETH: %s", address(wETH));
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


    function _printWalletWethBalance(address wallet) private view {
        console.log();
        console.log(" Balances for %s", wallet);

        uint256 balance = wETH.balanceOf(wallet);
        console.log("         wETH: %s [%d]", _toDecimalString(balance, 18), balance);
        console.log();
    }

    function _printWalletReflectBalance(address wallet) private view {
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
            _printWalletReflectBalance(wallet);


        vm.startPrank(FundWallet);
        TokenContract.transfer(wallet, amount);
        vm.stopPrank();

        if (verbose)
            _printWalletReflectBalance(wallet);

        uint256 newUserbalance = TokenContract.balanceOf(wallet);
        assertEq(amount, newUserbalance - oldUserbalance, "User balance change must be equal airdrop size");
    }

    
    function testPairLaunch() public {
        console.log("Creating Uniswap V2 pair");

        deal(address(wETH), address(TokenContract), 1_000_000 ether);

        vm.startPrank(Owner);
        IUniswapV2Pair pair = IUniswapV2Pair(TokenContract.LaunchUniV2Pool(10));
        vm.stopPrank();

        if (pair.token0() == address(TokenContract)) {
            assertEq(address(TokenContract), pair.token0(), "Pair token 0");
            assertEq(address(wETH), pair.token1(), "Pair token 1");
            assertEq(false, TokenContract.DexReflectIsToken1(), "Reflect is token 0");
        } else {
            assertEq(address(wETH), pair.token0(), "Pair token 0");
            assertEq(address(TokenContract), pair.token1(), "Pair token 1");
            assertEq(true, TokenContract.DexReflectIsToken1(), "Reflect is token 1");
        }

        assertEq(block.number + 10, TokenContract.RegularTaxBlock(), "Regular tax block number");

        assertLt(0, pair.balanceOf(address(TokenContract)), "Liqudity balance");
        assertTrue(TokenContract.Taxable(address(pair)), "Uniswap pair is taxed");
        assertEq(address(pair), address(TokenContract.DEX()), "DEX address");

        assertEq(TokenContract.totalSupply(), TokenContract.balanceOf(address(pair)),"Pair $REFLECT balance");
        assertEq(1_000_000 ether, wETH.balanceOf(address(pair)),"Pair wETH balance");

        console.log("Uniswap V2 pair created");
    }

    function testSellCollectedRewards() public {
        testPairLaunch();

        deal(address(TokenContract), address(TokenContract), 100_000 ether);

        console.log("Initial state");

        _printWalletReflectBalance(address(TokenContract));
        _printWalletWethBalance(address(TokenContract));
        _printWalletWethBalance(TeamWallet);

        (, uint32 lastSwapTime) = TokenContract.RewardCycleData();
        assertEq(0, lastSwapTime, "reward swap time");

        vm.startPrank(Owner);
        TokenContract.FixEthRewards(0);
        vm.stopPrank();

        console.log("After swap");

        _printWalletReflectBalance(address(TokenContract));
        _printWalletWethBalance(address(TokenContract));
        _printWalletWethBalance(TeamWallet);

        assertLt(0, wETH.balanceOf(address(TokenContract)), "wETH balance token");
        assertLt(0, wETH.balanceOf(TeamWallet), "wETH balance token");
        (, lastSwapTime) = TokenContract.RewardCycleData();
        assertEq(block.timestamp, lastSwapTime, "reward swap time");
    }

    function testSellCollectedRewardsEmptyBalance() public {
        testPairLaunch();

        console.log("Initial state");

        _printWalletReflectBalance(address(TokenContract));
        _printWalletWethBalance(address(TokenContract));
        _printWalletWethBalance(TeamWallet);

        (, uint32 lastSwapTime) = TokenContract.RewardCycleData();
        assertEq(0, lastSwapTime, "reward swap time");

        vm.startPrank(Owner);
        vm.expectRevert(bytes("Empty balance"));
        TokenContract.FixEthRewards(0);
        vm.stopPrank();
    }

    function testSellCollectedRewardsHighPrice() public {
        testPairLaunch();

        deal(address(TokenContract), address(TokenContract), 100_000 ether);

        console.log("Initial state");

        _printWalletReflectBalance(address(TokenContract));
        _printWalletWethBalance(address(TokenContract));
        _printWalletWethBalance(TeamWallet);

        (, uint32 lastSwapTime) = TokenContract.RewardCycleData();
        assertEq(0, lastSwapTime, "reward swap time");

        vm.startPrank(Owner);
        vm.expectRevert(bytes("Price slippage too small"));
        TokenContract.FixEthRewards(1e28); // 1 $REFLECT = 1 ETH
        vm.stopPrank();        
    }


    struct _rewardDistroState {
        address[]  users;
        uint256[]  sizes;
        uint256    totalAirdrop;
        uint256[]  oldBalances;
    }

    function testRewardDistro() public {
        testPairLaunch();


        _rewardDistroState memory lState;

        lState.users       = new address[](4);
        lState.sizes       = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        //           100_0000
        lState.sizes[0] =    (2_0000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[1] =    (1_9000 * lState.totalAirdrop) / 100_0000;

        lState.sizes[2] =    (  9000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  8000 * lState.totalAirdrop) / 100_0000;

        vm.startPrank(Owner);
        TokenContract.ExcludeWalletFromRewards(FundWallet);
        vm.stopPrank();
        deal(address(TokenContract), FundWallet, lState.totalAirdrop);

        for (uint256 i = 0; i < lState.users.length ; i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        deal(address(TokenContract), address(TokenContract), 100_000 ether);

        console.log("Selling rewards");

        vm.startPrank(Owner);
        TokenContract.FixEthRewards(0);
        vm.stopPrank();

        uint256 rewardBalance = wETH.balanceOf(address(TokenContract));

        assertLt(0, rewardBalance, "wEth reward balance");

        console.log("Distributing rewards");

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle(0, true, 100_00);
        vm.stopPrank();

        console.log("Reward balances");

        for (uint256 i = 0; i < lState.users.length ; i++) {
            _printWalletWethBalance(lState.users[i]);
        }

        assertEq(rewardBalance * 30_00 * 50_00 / (100_00 * 100_00), wETH.balanceOf(lState.users[0]), "wEth balance user 0");
        assertEq(rewardBalance * 30_00 * 50_00 / (100_00 * 100_00), wETH.balanceOf(lState.users[1]), "wEth balance user 1");
        assertEq(rewardBalance * 23_00 * 50_00 / (100_00 * 100_00), wETH.balanceOf(lState.users[2]), "wEth balance user 2");
        assertEq(rewardBalance * 23_00 * 50_00 / (100_00 * 100_00), wETH.balanceOf(lState.users[3]), "wEth balance user 3");
    }


    
    function testRewardDistroWithBoosted() public {
        testPairLaunch();


        _rewardDistroState memory lState;

        lState.users       = new address[](4);
        lState.sizes       = new uint256[](lState.users.length);
        lState.oldBalances = new uint256[](lState.users.length);

        lState.totalAirdrop = TokenContract.totalSupply();

        for (uint256 i = 0; i < lState.users.length; i++) {
            lState.users[i] = _allocateBurner();
        }

        lState.sizes[0] =    (1_0000 * lState.totalAirdrop) / 100_0000 - 100; //2nd tier
        lState.sizes[1] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[2] =    (  7000 * lState.totalAirdrop) / 100_0000;
        lState.sizes[3] =    (  7000 * lState.totalAirdrop) / 100_0000;

        vm.startPrank(Owner);
        TokenContract.ExcludeWalletFromRewards(FundWallet);
        vm.stopPrank();
        deal(address(TokenContract), FundWallet, lState.totalAirdrop);

        for (uint256 i = 0; i < lState.users.length ; i++) {
            console.log("User: %d", i);

            _fundWallet(lState.users[i], lState.sizes[i]);
            console.log("++++++++++++++++++++++++ NEXT USER ++++++++++++++++++++++++++");
        }

        console.log("Boosting wallet 1");
        
        vm.startPrank(Owner);
        TokenContract.BoostWallet(lState.users[1]);
        vm.stopPrank();
   
        deal(address(TokenContract), address(TokenContract), 100_000 ether);

        console.log("Selling rewards");

        vm.startPrank(Owner);
        TokenContract.FixEthRewards(0);
        vm.stopPrank();

        uint256 rewardBalance = wETH.balanceOf(address(TokenContract));

        assertLt(0, rewardBalance, "wEth reward balance");

        console.log("Distributing rewards");

        vm.startPrank(Owner);
        TokenContract.LaunchNewRewardCycle(0, true, 100_00);
        vm.stopPrank();

        console.log("Reward balances");

        for (uint256 i = 0; i < lState.users.length ; i++) {
            _printWalletWethBalance(lState.users[i]);
        }

        assertEq(rewardBalance * 23_00 * 24_75 / (100_00 * 100_00), wETH.balanceOf(lState.users[0]), "wEth balance user 0");
        assertEq(rewardBalance * 23_00 * 25_75 / (100_00 * 100_00), wETH.balanceOf(lState.users[1]), "wEth balance user 1");
        assertEq(rewardBalance * 23_00 * 24_75 / (100_00 * 100_00), wETH.balanceOf(lState.users[2]), "wEth balance user 2");
        assertEq(rewardBalance * 23_00 * 24_75 / (100_00 * 100_00), wETH.balanceOf(lState.users[3]), "wEth balance user 3");
    }

    function testEmgRewardDistro() public {
        deal(address(wETH), address(TokenContract), 100 ether);

        address[] memory wallets = new address[](2);
        uint256[] memory sizes = new uint256[](2);

        wallets[0] = _allocateBurner();
        wallets[1] = _allocateBurner();

        sizes[0] = 49 ether;
        sizes[1] = 50 ether;

        console.log("Initial state");
        _printWalletWethBalance(wallets[0]);
        _printWalletWethBalance(wallets[1]);

        assertEq(0, wETH.balanceOf(wallets[0]), "wEth balance 0");
        assertEq(0, wETH.balanceOf(wallets[1]), "wEth balance 1");

        vm.startPrank(Owner);
        TokenContract.DistributeReward(wallets, sizes, 0);
        vm.stopPrank();
        
        console.log("After distribution");
        _printWalletWethBalance(wallets[0]);
        _printWalletWethBalance(wallets[1]);

        assertEq(49 ether, wETH.balanceOf(wallets[0]), "wEth balance 0");
        assertEq(50 ether, wETH.balanceOf(wallets[1]), "wEth balance 1");
    }
}