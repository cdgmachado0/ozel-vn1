// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


// import {ozToken} from "../ozToken.sol";
import {AppStorage, NewToken} from "../AppStorage.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {ozTokenProxy} from "../ozTokenProxy.sol";
import {wozTokenProxy} from "../wozTokenProxy.sol";
import {ozIToken} from "../interfaces/ozIToken.sol";
import "../Errors.sol";
// import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// import "hardhat/console.sol";
import "forge-std/console.sol";


//Put here, inside createOzToken, the creation of the wozToken also. 
//I added already all to Setup.sol
//What's left is to create the wozToken contract and call the getHello function
//on the implementation to see if it works (use as guide ozToken.sol)


contract ozTokenFactory {

    using Helpers for address[];

    AppStorage internal s;

    event TokenCreated(address indexed ozToken);
    
    //Wrapper function - returns address of ozToken
    function createOzToken(
        address underlying_,
        // string memory name_,
        // string memory symbol_
        NewToken memory ozToken_,
        NewToken memory wozToken_
    ) external returns(address, address) { //put an onlyOwner

        if (isInRegistry(underlying_)) revert OZError12(underlying_);
        if (underlying_ == address(0)) revert OZError11(underlying_);

        //ozToken
        bytes memory ozData = abi.encodeWithSignature( 
            "initialize(address,address,string,string)", 
            underlying_, s.ozDiamond, ozToken_.name, ozToken_.symbol
        );

        ozTokenProxy newToken = new ozTokenProxy(s.ozBeacon, ozData);
        
        //wozToken
        bytes memory wozData = abi.encodeWithSignature(
            "initialize(string,string,address)", 
            wozToken_.name, wozToken_.symbol, address(newToken)
        );

        wozTokenProxy newWozToken = new wozTokenProxy(s.wozBeacon, wozData);

        //------
        _saveInRegistry(address(newToken), underlying_);

        return (address(newToken), address(newWozToken));
    }

    //*** check the note in AppStorage for ozTokenRegistryMap*/
    function _saveInRegistry(address newOzToken_, address underlying_) private {
        s.ozTokenRegistry.push(newOzToken_);
        s.ozTokenRegistryMap[newOzToken_] = true; //<--- remove
        s.ozTokens[underlying_] = newOzToken_;
        emit TokenCreated(newOzToken_);
    }

    function getOzTokenRegistry() external view returns(address[] memory) {
        return s.ozTokenRegistry;
    }

    function isInRegistry(address underlying_) public view returns(bool) {
        uint length = s.ozTokenRegistry.length;
        if (length == 0) return false;

        for (uint i=0; i < length; i++) {
            if (ozIToken(s.ozTokenRegistry[i]).asset() == underlying_) return true; 
        }

        return false;
    }

    

}