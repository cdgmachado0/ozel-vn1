// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {TestMethods} from "./TestMethods.sol";
import {ozIToken} from "../../contracts/interfaces/ozIToken.sol";
import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {Type, Dir} from "./AppStorageTests.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AmountsIn} from "../../contracts/AppStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/Errors.sol";
import {Dummy1} from "./Dummy1.sol";
import {NewToken} from "../../contracts/AppStorage.sol";
import "@prb/math/src/UD60x18.sol";
import {PRBMathCastingUint256} from "@prb/math/src/casting/Uint256.sol";

import "forge-std/console.sol";


contract ozTokenTest is TestMethods {

    using SafeERC20 for IERC20;
    using PRBMathCastingUint256 for uint;

    // uint SCALE = 1e18;
    // uint HALF_SCALE = 5e17;
    // uint LOG2_E = 1442695040888963407;
    // uint MAX_SD59x18 = 57896044618658097711785492504343953926634992332820282019728792003956564819967;

    //Tests that the try/catch on ozToken's mint() catches errors on safeTransfers 
    function test_mint_catch_internal_errors() public {
        //Pre-conditions  
        (ozIToken ozERC20_1,) = _createOzTokens(usdtAddr, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, true);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();

        (bytes memory data) = _createDataOffchain(
            ozERC20_1, amountIn, ALICE_PK, alice, testToken, Type.IN
        );

        (uint[] memory minAmountsOut,,,) = HelpersLib.extract(data);

        vm.startPrank(alice);
        IERC20(testToken).safeApprove(address(OZ), amountIn);

        AmountsIn memory amounts = AmountsIn(
            amountIn,
            minAmountsOut
        );

        //Actions
        vm.expectRevert(
            abi.encodeWithSelector(OZError22.selector, 'SafeERC20: low-level call failed')
        );

        ozERC20_1.mint(abi.encode(amounts, alice), alice);         
        vm.stopPrank();
    }


    //Tests that the try/catch on ozToken's redeem() catches errors on safeTransfers
    function test_redeem_catch_internal_errors() public {
        //Pre-conditions
        _changeSlippage(uint16(9900));
        _dealUnderlying(Quantity.BIG, false);

        uint decimalsUnderlying = 10 ** IERC20Permit(testToken).decimals();
        uint amountIn = IERC20Permit(testToken).balanceOf(alice);
        assertTrue(amountIn == 1_000_000 * decimalsUnderlying);

        (ozIToken ozERC20,) = _createAndMintOzTokens(testToken, amountIn, alice, ALICE_PK, true, true, Type.IN);
        uint balanceOzUsdcAlice = ozERC20.balanceOf(alice);
        assertTrue(balanceOzUsdcAlice > 977_000 * 1 ether && balanceOzUsdcAlice < 1_000_000 * 1 ether);

        uint ozAmountIn = ozERC20.balanceOf(alice);
        testToken = address(ozERC20);

        bytes memory redeemData = _createDataOffchain(
            ozERC20, ozAmountIn, ALICE_PK, alice, testToken, Type.OUT
        );

        //Actions
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(OZError22.selector, 'STF')
        );
        ozERC20.redeem(redeemData, alice); 

        vm.stopPrank();
    }


    function test_minting_different_owner_msgSender() public returns(Dummy1, ozIToken) {
        //Pre-conditions  
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        _startCampaign();

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, true);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();

        Dummy1 dummy1 = new Dummy1(address(ozERC20), address(OZ));

        vm.startPrank(alice);
        IERC20(testToken).approve(address(OZ), amountIn);

        //Actions
        bool success = dummy1.mintOz(testToken, amountIn); 
        assertTrue(success);

        uint secs = 15;
        _accrueRewards(secs);

        uint claimed = OZ.claimReward();
        vm.stopPrank();

        //Post-conditions
        vm.clearMockedCalls();
        uint ozBalanceAlice = ozERC20.balanceOf(alice);

        assertTrue(ozBalanceAlice > 99 * 1e18 && ozBalanceAlice < rawAmount * 1e18);
        assertTrue((_getRewardRate() * secs) / 100 == claimed / 100);

        return (dummy1, ozERC20);
    }


    function test_redeeming_different_owner_msgSender() public {
        //Pre-conditions
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, true);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();

        Dummy1 dummy1 = new Dummy1(address(ozERC20), address(OZ));

        vm.startPrank(alice);
        IERC20(testToken).approve(address(OZ), amountIn);

        bool success = dummy1.mintOz(testToken, amountIn); 
        assertTrue(success);
        
        uint ozBalanceAlicePre = ozERC20.balanceOf(alice);
        uint testTokenBalanceAlicePre = IERC20(testToken).balanceOf(alice);

        //Action
        ozERC20.approve(address(OZ), ozBalanceAlicePre);
        success = dummy1.redeemOz(ozBalanceAlicePre);
        assertTrue(success);

        vm.stopPrank();

        //Post-conditions
        uint ozBalanceAlicePost = ozERC20.balanceOf(alice);
        uint testTokenBalanceAlicePost = IERC20(testToken).balanceOf(alice);

        assertTrue(ozBalanceAlicePre > 99 * 1e18 && ozBalanceAlicePre < rawAmount * 1e18);
        assertTrue(ozBalanceAlicePost == 0);
        assertTrue(testTokenBalanceAlicePre == 0);
        assertTrue(testTokenBalanceAlicePost > 99 * 1e18 && testTokenBalanceAlicePost < rawAmount * 1e18);
    }


    function test_rETH_USD_down() public {
        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();

        _mintOzTokens(ozERC20, alice, testToken, amountIn);
        console.log('totalShares *****: ', ozERC20.totalShares());
        console.log('sharesOf: ', ozERC20.sharesOf(alice));

        uint balPre = ozERC20.balanceOf(alice);
        console.log('ozBal alice - pre: ', balPre);

        _mock_ETH_trend(Dir.UP, 400);
        
        uint balPost = ozERC20.balanceOf(alice);
        console.log('ozBal alice - post: ', balPost);

        _mock_rETH_ETH(Dir.UP, 200);

        balPost = ozERC20.balanceOf(alice);
        console.log('ozBal alice - post reth only: ', balPost);

        _mock_ETH_trend(Dir.DOWN, 500);

        balPost = ozERC20.balanceOf(alice);
        console.log('ozBal alice - post down: ', balPost);
    }


    function test_x() public {
        //check the mock functions, if they're returning correctly
        //finish down test
        //continue with APR test using either rETH_ETH value that goes constantly up, or...
        //using USD values, but would need to use Chainlink for historical data and comparrison

        (ozIToken ozERC20,) = _createOzTokens(testToken, "1");

        (uint rawAmount,,) = _dealUnderlying(Quantity.SMALL, false);
        uint amountIn = rawAmount * 10 ** IERC20Permit(testToken).decimals();
        console.log('amountIn: ', amountIn);
        
        _mintOzTokens(ozERC20, alice, testToken, amountIn);

        uint balPre = ozERC20.balanceOf(alice);
        console.log('ozBal alice - pre: ', balPre);

        _mock_rETH_ETH();

        uint balPost = ozERC20.balanceOf(alice);
        console.log('ozBal alice: ', balPost);

        uint delta = (balPost - balPre) * 1e18;
        console.log('ozBal delta - amp: ', delta);
        console.log('ozBal delta - no amp: ', balPost - balPre);

        uint apr = uint(delta / amountIn) * uint(uint(365) / uint(30)) * 100;
        console.log('apr: ', apr);

       //------
        console.log('-----');

        uint rethUsd = OZ.rETH_USD();
        console.log('rethUsd: ', rethUsd);

        uint ethUsd = OZ.ETH_USD();
        console.log('ethUsd: ', ethUsd);
    }

    //----------------------------------------      


    function test_y() public {
        

        // uint num = 54802476401439357 * 1e18;

        // UD60x18 y = num.intoUD60x18();
        // uint num2 = intoUint256(y.ln());
        // console.log('num2: ', num2);

        //-----

        uint a1 = 1934464428151493937044;
        uint a2 = 1837741206733939183658;

        uint b = 54802476401439357 * 1e18;
        uint base = 1108895170451311786;
        UD60x18 b_prb = b.intoUD60x18();
        uint b_prime = intoUint256(b_prb.ln());

        uint N = 1e18;
        uint adjustment = base * 1e17;

        uint result1 = ((a1 - base) * b_prime) / N + adjustment;
        uint result2 = ((a2 - base) * b_prime) / N + adjustment;

        console.log('result1: ', result1);
        console.log('result2: ', result2);

    }



}