// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {AmountsIn} from "../../contracts/AppStorage.sol";
import {Setup} from "./Setup.sol";
import {ozIDiamond} from "../../contracts/interfaces/ozIDiamond.sol";
import {OZError13} from "../../contracts/Errors.sol";


contract ROImoduleL1Test is Setup {

    AmountsIn amts = AmountsIn(uint(0), uint(0), uint(0));

    /**
     * Tests unauthorized access directly to the useUnderlying.
     */
    function test_unauth_access_direct_useUnderlying() public {
        vm.expectRevert(
            abi.encodeWithSelector(OZError13.selector, alice)
        );
        vm.prank(alice);
        ozIDiamond(address(roi)).useUnderlying(address(0), address(0), amts);
    }

    /**
     * Tests unauthorized access to userUnderlying through ozDiamond.
     */
    function test_unauth_access_diamond_useUnderlying() public {
        vm.expectRevert(
            abi.encodeWithSelector(OZError13.selector, alice)
        );
        vm.prank(alice);
        OZ.useUnderlying(address(0), address(0), amts);
    }


    /**
     * Tests unauthorized access directly to the useOzTokens function.
     */
    function test_unauth_access_direct_useOzTokens() public {
        vm.expectRevert(
            abi.encodeWithSelector(OZError13.selector, alice)
        );
        vm.prank(alice);
        ozIDiamond(address(roi)).useOzTokens(address(0), new bytes(0));
    }

    /**
     * Tests unauthorized access to userUnderlying through ozDiamond.
     */
    function test_unauth_access_diamond_useOzTokens() public {
        vm.expectRevert(
            abi.encodeWithSelector(OZError13.selector, alice)
        );
        vm.prank(alice);
        OZ.useOzTokens(address(0), new bytes(0));
    }



}