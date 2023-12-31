// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {Asset} from "../../contracts/AppStorage.sol";
import {TestMethods} from "./TestMethods.sol";
import {ozIToken} from "../../contracts/interfaces/ozIToken.sol";
import {Type} from "./AppStorageTests.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {AmountsIn} from "../../contracts/AppStorage.sol";
import {OZError10} from "../../contracts/Errors.sol";

import "forge-std/console.sol";


contract OtherTests is TestMethods {

    function test_totalUnderlying() public {
        //Pre-condition + Action
        _minting_approve_smallMint();

        //Post-conditions
        uint totalUSD = OZ.totalUnderlying(Asset.USD);
        uint ROUNDER = 1e1;
        uint ozDiamondRethBalance = IERC20Permit(rEthAddr).balanceOf(address(OZ));

        assertTrue(totalUSD / ROUNDER == ((ozDiamondRethBalance * OZ.rETH_USD()) / 1 ether^2)/ ROUNDER);
    }

    /**
     * An inflation attack wouldn't be possible since it'd be filtered out 
     * by Balancer when trying to do one of the internal swaps
     */
    function test_inflation_attack() public {
        /**
         * Pre-conditions
         */
        _dealUnderlying(Quantity.BIG);
        address attacker = alice;
        address victim = charlie;
        uint amountIn = 1;

        ozIToken ozERC20 = ozIToken(OZ.createOzToken(
            testToken, "Ozel-ERC20", "ozERC20"
        ));
        
        (bytes memory data) = _createDataOffchain(
            ozERC20, amountIn, ALICE_PK, attacker, Type.IN
        );

        (uint[] memory minAmountsOut,,,) = HelpersLib.extract(data);

        vm.startPrank(attacker);

        IERC20Permit(testToken).approve(address(ozDiamond), amountIn);

        AmountsIn memory amounts = AmountsIn(
            amountIn,
            minAmountsOut[0],
            minAmountsOut[1]
        );

        bytes memory mintData = abi.encode(amounts, attacker);

        //The flow of the attack would revert here before the attack even happens.
        vm.expectRevert(
            abi.encodeWithSelector(OZError10.selector, 'BAL#510')
        );
        ozERC20.mint(mintData); 

        /**
         * Action (attack)
         */
        amountIn = 10_000e18 - 1;

        _createAndMintOzTokens(
            address(ozERC20), amountIn, attacker, ALICE_PK, false, true, Type.IN
        );

        /**
         * Post-conditions
         */
        amountIn = 19999e18;

        _createAndMintOzTokens(
            address(ozERC20), amountIn, charlie, CHARLIE_PK, false, true, Type.IN
        );

        uint balVictim = ozERC20.balanceOf(victim);
        assertTrue(balVictim > 1);
    }


    function test_ozTokenRegistry() public {
        //Action
        _minting_approve_smallMint();

        //Post-conditions
        assertTrue(OZ.getOzTokenRegistry().length == 1);
        assertTrue(OZ.isInRegistry(testToken));
    }

}