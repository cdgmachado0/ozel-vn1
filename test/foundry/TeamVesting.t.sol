// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {TestMethods} from "./TestMethods.sol";
import {IOZL} from "../../contracts/interfaces/IOZL.sol";

import "forge-std/console.sol";


contract TeamVestingTest is TestMethods {

    function test_vesting_releasing() public {
        //Pre-conditions
        assertTrue(address(teamVesting) != address(0));
        assertTrue(teamVesting.releasable() == 0);
        assertTrue(teamVesting.vestedAmount(uint64(block.timestamp)) == 0);
        IOZL OZL = IOZL(address(ozlProxy));
        
        vm.warp(startTimeTeamVesting + block.timestamp + 182 days); //Action 1

        uint relesable = teamVesting.releasable();
        uint vested = teamVesting.vestedAmount();
        assertTrue(relesable == vested);

        teamVesting.release(); //Action 2
        uint beneficiaryBalance = OZL.balanceOf(teamBeneficiary);
        assertTrue(beneficiaryBalance == vested);

        relesable = teamVesting.releasable();
        vested = teamVesting.vestedAmount();
    
        vm.warp(block.timestamp + 183 days); //Action 3

        relesable = teamVesting.releasable();
        assertTrue(relesable + beneficiaryBalance == teamAmount);

        vested = teamVesting.vestedAmount();
        assertTrue(vested == teamAmount);
    }



}