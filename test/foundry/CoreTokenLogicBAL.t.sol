// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import "../../contracts/facets/ozTokenFactory.sol";
import {Setup} from "./Setup.sol";
import {ozIToken} from "../../contracts/interfaces/ozIToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IQueries, IPool, IAsset, IVault} from "../../contracts/interfaces/IBalancer.sol";
import {Helpers} from "../../contracts/libraries/Helpers.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
// import "../../lib/forge-std/src/interfaces/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {AmountsIn, AmountsOut} from "../../contracts/AppStorage.sol";
import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {HelpersLib} from "./HelpersLib.sol";
// import "solady/src/utils/FixedPointMathLib.sol";
import {FixedPointMathLib} from "../../contracts/libraries/FixedPointMathLib.sol";
import {Type, RequestType, ReqIn, ReqOut} from "./AppStorageTests.sol";
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ozToken} from "../../contracts/ozToken.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {BaseMethods} from "./BaseMethods.sol";

import "forge-std/console.sol";


/**
 * Tests the minting, redeeming, and rebasing logic of the ozToken contract
 * when using Balancer as the logic mechanism. 
 */
contract CoreTokenLogicBALtest is BaseMethods {

    using FixedPointMathLib for uint;


    /**
     * Mints a small quantity of ozUSDC (~100) through a Balancer swap
     */
    function test_minting_approve_smallMint_swapBalancer() public {
        //Pre-condition
        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();

        //Action
        (ozIToken ozERC20, uint sharesAlice) = _createAndMintOzTokens(
            testToken, amountIn, alice, ALICE_PK, true, false, Type.IN
        );

        //Post-conditions
        assertTrue(address(ozERC20) != address(0));
        assertTrue(sharesAlice == rawAmount * ( 10 ** IERC20Permit(testToken).decimals() ));
    }

    //--------
    function test_minting_approve_smallMint_rocketPool() public {
        //Pre-condition
        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        _modifyRocketPoolDepositMaxLimit();

        //Action
        (ozIToken ozERC20, uint sharesAlice) = _createAndMintOzTokens(
            testToken, amountIn, alice, ALICE_PK, true, false, Type.IN
        );

        //Post-conditions
        assertTrue(address(ozERC20) != address(0));
        assertTrue(sharesAlice == rawAmount * ( 10 ** IERC20Permit(testToken).decimals() ));
    }
    //---------


    /**
     * Mints a big quantity of ozUSDC (~1M)
     */
    function test_minting_approve_bigMint() public {
        //Pre-condition
        (uint rawAmount,,) = _dealUnderlying(Quantity.BIG);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        _changeSlippage(9900);

        //Action
        (ozIToken ozERC20, uint sharesAlice) = _createAndMintOzTokens(
            testToken, amountIn, alice, ALICE_PK, true, false, Type.IN
        );

        //Post-conditions
        assertTrue(address(ozERC20) != address(0));
        assertTrue(sharesAlice == rawAmount * ( 10 ** IERC20Permit(testToken).decimals() ));
    }


    /**
     * Mints a small quantity of ozTokens using EIP2612
     */
    function test_minting_eip2612() public { 
        /**
         * Pre-conditions + Actions (creating of ozTokens)
         */
        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL);

        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        (ozIToken ozERC20, uint sharesAlice) = _createAndMintOzTokens(
            testToken, amountIn, alice, ALICE_PK, true, true, Type.IN
        );

        amountIn = (rawAmount / 2) * 10 ** IERC20Permit(testToken).decimals();
        (, uint sharesBob) = _createAndMintOzTokens(
            address(ozERC20), amountIn, bob, BOB_PK, false, true, Type.IN
        );

        amountIn = (rawAmount / 4) * 10 ** IERC20Permit(testToken).decimals();
        (, uint sharesCharlie) = _createAndMintOzTokens(
            address(ozERC20), amountIn, charlie, CHARLIE_PK, false, true, Type.IN
        );

        //Post-conditions
        assertTrue(address(ozERC20) != address(0));
        assertTrue(sharesAlice == rawAmount * ( 10 ** IERC20Permit(testToken).decimals() ));
        assertTrue(sharesAlice / 2 == sharesBob);
        assertTrue(sharesAlice / 4 == sharesCharlie);
        assertTrue(sharesBob == sharesCharlie * 2);
        assertTrue(sharesBob / 2 == sharesCharlie);

        uint balanceAlice = ozERC20.balanceOf(alice);
        uint balanceBob = ozERC20.balanceOf(bob);
        uint balanceCharlie = ozERC20.balanceOf(charlie);

        assertTrue(balanceAlice / 2 == balanceBob);
        assertTrue(balanceAlice / 4 == balanceCharlie);
        assertTrue(balanceBob == balanceCharlie * 2);
        assertTrue(balanceBob / 2 == balanceCharlie);

        assertTrue(ozERC20.totalSupply() == balanceAlice + balanceCharlie + balanceBob);
        assertTrue(ozERC20.totalAssets() / 10 ** IERC20Permit(testToken).decimals() == rawAmount + rawAmount / 2 + rawAmount / 4);
        assertTrue(ozERC20.totalShares() == sharesAlice + sharesBob + sharesCharlie);
    }   

    
    /**
     * Transfer ozTokens between accounts
     */
    function test_transfer() public {
        //Pre-conditions
        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL);

        (ozIToken ozERC20,) = _createAndMintOzTokens(
            testToken, rawAmount * 10 ** IERC20Permit(testToken).decimals(), alice, ALICE_PK, true, true, Type.IN
        );

        uint balAlice = ozERC20.balanceOf(alice);
        assertTrue(balAlice > 99 * 1 ether && balAlice < rawAmount * 1 ether);

        uint balBob = ozERC20.balanceOf(bob);
        assertTrue(balBob == 0);

        //Action
        vm.prank(alice);
        ozERC20.transfer(bob, balAlice);

        //Post-conditions
        balAlice = ozERC20.balanceOf(alice);
        assertTrue(balAlice > 0 && balAlice < 0.000001 * 1 ether);

        balBob = ozERC20.balanceOf(bob);
        assertTrue(balBob > 99 * 1 ether && balBob < rawAmount * 1 ether);
    }

    /**
     * From 1M USDC balance, mint 1M and redeem 1M
     */
    function test_redeeming_bigBalance_bigMint_bigRedeem() public {
        //Pre-conditions
        _changeSlippage(9900);
        _dealUnderlying(Quantity.BIG);

        uint decimalsUnderlying = 10 ** IERC20Permit(testToken).decimals();
        uint amountIn = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(amountIn == 1_000_000 * decimalsUnderlying);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceOzUsdcAlice = ozERC20.balanceOf(alice);
        assertTrue(balanceOzUsdcAlice > 980_000 * 1 ether && balanceOzUsdcAlice < 1_000_000 * 1 ether);

        uint ozAmountIn = ozERC20.balanceOf(alice);
        testToken = address(ozERC20);

        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);

        //Action
        vm.startPrank(alice);
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        ozERC20.redeem(redeemData); 

        //Post-conditions
        testToken = usdcAddr;
        uint balanceUnderlyingAlice = IERC20Permit(testToken).balanceOf(alice);
       
        assertTrue(balanceUnderlyingAlice > 998_000 * decimalsUnderlying && balanceUnderlyingAlice < 1_000_000 * decimalsUnderlying);
        assertTrue(ozERC20.balanceOf(alice) == 0);
    }


    /**
     * From 1M USDC balance, mint and redeem a small part (100 USDC)
     */
    function test_redeeming_bigBalance_smallMint_smallRedeem() public {
        //Pre-conditions
        _changeSlippage(9900);
        _dealUnderlying(Quantity.BIG);

        uint decimalsUnderlying = 10 ** IERC20Permit(testToken).decimals();
        uint amountIn = 100 * decimalsUnderlying;
        assertTrue(IERC20Permit(usdcAddr).balanceOf(alice) == 1_000_000 * decimalsUnderlying);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceUsdcAlicePostMint = IERC20Permit(testToken).balanceOf(alice);

        uint ozAmountIn = ozERC20.balanceOf(alice);
        assertTrue(ozAmountIn > 99 * 1 ether && ozAmountIn < 100 * 1 ether);
        testToken = address(ozERC20);

        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);

        //Action
        vm.startPrank(alice);
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        uint underlyingOut = ozERC20.redeem(redeemData); 

        //Post-conditions
        testToken = usdcAddr;
        uint balanceUnderlyingAlice = IERC20Permit(testToken).balanceOf(alice);
        uint finalUnderlyingNetBalanceAlice = balanceUsdcAlicePostMint + underlyingOut;
        
        assertTrue(ozERC20.balanceOf(alice) == 0);
        assertTrue(underlyingOut > 99 * decimalsUnderlying && underlyingOut < 100 * decimalsUnderlying);
        assertTrue(balanceUnderlyingAlice == finalUnderlyingNetBalanceAlice);
        assertTrue(finalUnderlyingNetBalanceAlice > 999_000 * decimalsUnderlying && finalUnderlyingNetBalanceAlice < 1_000_000 * decimalsUnderlying);
    }


    /** REFERENCE
     * Mints 1M of ozTokens, then rebalances Uniswap and Balancer pools, 
     * and redeems a small portio of ozUSDC. 
     */
    function test_redeeming_bigBalance_bigMint_smallRedeem() public {
        /**
         * Pre-conditions
         */
        //Deals big amounts of USDC to testers.
        _dealUnderlying(Quantity.BIG);
        uint amountIn = IERC20Permit(testToken).balanceOf(alice);
        uint rawAmount = 100;
        assertTrue(amountIn == 1_000_000 * 1e6);

        //Changes the default slippage to 99% so the swaps don't fail.
        _changeSlippage(9900);

        //Gets the pre-swap pool values.
        bytes32 oldSlot0data = vm.load(wethUsdPoolUni, bytes32(0));
        (bytes32 oldSharedCash, bytes32 cashSlot) = _getSharedCashBalancer();

        //Creates an ozToken and mints some.
        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceUsdcAlicePostMint = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceUsdcAlicePostMint == 0);

        //Returns balances to pre-swaps state so the rebase algorithm can be prorperly tested.
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        uint ozAmountIn = rawAmount * 1 ether;
        testToken = address(ozERC20);

        //Creates offchain the token-amount variables needed for safe protocol execution.
        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);
    
        /**
         * Action
         */
        vm.startPrank(alice);

        //Redeems ozUSDC for USDC.
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        uint underlyingOut = ozERC20.redeem(redeemData);
        vm.stopPrank();

        /**
         * Post-conditions
         */
        uint balanceAliceUnderlying = IERC20Permit(usdcAddr).balanceOf(alice);

        assertTrue(balanceAliceUnderlying < rawAmount * 1e6 && balanceAliceUnderlying > 99 * 1e6);
        assertTrue(balanceAliceUnderlying == underlyingOut);
    }


    /**
     * Used 100 USDC to mint ozUSDC, where redeeming 1 ozUSDC, would
     * be ineligble so the MEV produced would be quite lower, proving the efficacy of the 
     * rebase algorithm, without the need of having to rebalance Uniswap and Balancer's pools.
     *
     * In this test, the "bigMint" is in relation to the amount being redeem (100:1)
     */
    function test_redeeming_multipleBigBalances_bigMints_smallRedeem() public {
        (,uint initMintAmountBob, uint initMintAmountCharlie) = _dealUnderlying(Quantity.SMALL);
        uint amountToRedeem = 1;

        // uint decimalsUnderlying = 10 ** IERC20Permit(testToken).decimals();
        uint amountIn = IERC20Permit(testToken).balanceOf(alice);
        // assertTrue(amountIn == 100 * 1e6);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceUsdcAlicePostMint = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceUsdcAlicePostMint == 0); 

        uint balanceOzBobPostMint = _createMintAssertOzTokens(bob, ozERC20, BOB_PK, initMintAmountBob);
        uint balanceOzCharliePostMint = _createMintAssertOzTokens(charlie, ozERC20, CHARLIE_PK, initMintAmountCharlie);

        uint ozAmountIn = amountToRedeem * 1 ether;
        testToken = address(ozERC20);
        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);

        //Action
        vm.startPrank(alice);
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        uint underlyingOut = ozERC20.redeem(redeemData);

        //Post-conditions
        uint balanceOzBobPostRedeem = ozERC20.balanceOf(bob);
        uint balanceOzCharliePostRedeem = ozERC20.balanceOf(charlie);
        uint basisPointsDifferenceBobMEV = (balanceOzBobPostMint - balanceOzBobPostRedeem).mulDivDown(10000, balanceOzBobPostMint);
        uint basisPointsDifferenceCharlieMEV = (balanceOzCharliePostMint - balanceOzCharliePostRedeem).mulDivDown(10000, balanceOzCharliePostMint);

        assertTrue(underlyingOut == IERC20Permit(usdcAddr).balanceOf(alice));
        assertTrue(basisPointsDifferenceBobMEV == 0);
        assertTrue(basisPointsDifferenceCharlieMEV == 0);
        assertTrue(underlyingOut > 998000 && underlyingOut < 1 * 1e6);
    }


    
    /**
     * Mints ~1M of ozUSDC, but redeems a portion of the balance (~700k)
     */
    function test_redeeming_bigBalance_bigMint_mediumRedeem() public {
        //Pre-conditions
        _changeSlippage(9900);
        _dealUnderlying(Quantity.BIG);

        bytes32 oldSlot0data = vm.load(wethUsdPoolUni, bytes32(0));
        (bytes32 oldSharedCash, bytes32 cashSlot) = _getSharedCashBalancer();

        uint amountIn = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(amountIn == 1_000_000 * 1e6);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceUsdcAlicePostMint = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(balanceUsdcAlicePostMint == 0);

        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        uint ozAmountIn = ozERC20.balanceOf(alice) / 10;
        testToken = address(ozERC20);

        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);

        //Action
        vm.startPrank(alice);
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        uint underlyingOut = ozERC20.redeem(redeemData);

        //Post-conditions
        uint percentageDiffAmounts = (ozAmountIn - (underlyingOut * 1e12)).mulDivDown(10000, ozAmountIn);

        //Measures that the difference between the amount of ozTokens that went in to
        //the amount of underlying that went out is less than 0.15%, which translates to
        //differences between pools balances during swaps. 
        uint percentageDiff = 15;
        assertTrue(percentageDiffAmounts < percentageDiff);
        vm.stopPrank();
    }


    function test_redeeming_eip2612() public {
        //Pre-conditions
        _dealUnderlying(Quantity.SMALL);
        uint amountIn = IERC20Permit(testToken).balanceOf(alice); 
        assertTrue(amountIn > 0);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);

        uint ozAmountIn = ozERC20.balanceOf(alice);
        testToken = address(ozERC20);
        
        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, _getPermitHash(alice, ozAmountIn));

        //Action
        vm.startPrank(alice);
        ozERC20.permit(
            alice,
            address(ozDiamond),
            ozAmountIn,
            block.timestamp,
            v, r, s
        );

        ozERC20.redeem(redeemData); 

        //Post-conditions
        testToken = usdcAddr;
        uint decimalsUnderlying = 10 ** IERC20Permit(testToken).decimals();
        uint balanceUnderlyingAlice = IERC20Permit(testToken).balanceOf(alice);

        assertTrue(balanceUnderlyingAlice > 99 * decimalsUnderlying && balanceUnderlyingAlice < 100 * decimalsUnderlying);
        assertTrue(ozERC20.totalSupply() == 0);
        assertTrue((ozERC20.totalAssets() / decimalsUnderlying) == 0);
        assertTrue((ozERC20.totalShares() / decimalsUnderlying) == 0);
        assertTrue((ozERC20.sharesOf(alice) / decimalsUnderlying) == 0);
        assertTrue((ozERC20.balanceOf(alice) / ozERC20.decimals()) == 0);
    }


    /**
     * This test proves that the rebasing algorithm works, and that the difference
     * between token balances is due to imbalanced pools after the test swaps
     */
    function test_redeeming_multipleBigBalances_bigMint_mediumRedeem() public {
        //Pre-conditions
        _changeSlippage(9900);
        _dealUnderlying(Quantity.BIG);

        bytes32 oldSlot0data = vm.load(wethUsdPoolUni, bytes32(0));
        (bytes32 oldSharedCash, bytes32 cashSlot) = _getSharedCashBalancer();

        uint amountIn = IERC20Permit(testToken).balanceOf(alice) / 2;

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        _createAndMintOzTokens(address(ozERC20), amountIn, bob, BOB_PK, false, false, Type.IN);
        _resetPoolBalances(oldSlot0data, oldSharedCash, cashSlot);

        uint ozAmountIn = ozERC20.balanceOf(alice) / 10;
        testToken = address(ozERC20);

        bytes memory redeemData = _createDataOffchain(ozERC20, ozAmountIn, ALICE_PK, alice, Type.OUT);

        // //Action
        vm.startPrank(alice);
        ozERC20.approve(address(ozDiamond), ozAmountIn);
        uint underlyingOut = ozERC20.redeem(redeemData);
        vm.stopPrank();

        // //Post-conditions
        uint percentageDiff = 15;
        uint percentageDiffAmounts = (ozAmountIn - (underlyingOut * 1e12)).mulDivDown(10000, ozAmountIn);
        assertTrue(percentageDiffAmounts < percentageDiff);
    }
}