// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/beacon/UpgradeableBeacon.sol)

pragma solidity 0.8.21;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AppStorage} from "../AppStorage.sol";
import "../Errors.sol";

import "forge-std/console.sol";


/**
 * @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
 * implementation contract, which is where they will delegate all function calls.
 *
 * An owner is able to change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
 */
 //Modified all of this contract
contract ozBeacon {

    AppStorage private s;

    /**
     * @dev Emitted when the implementation returned by the beacon is changed.
     */
    event Upgraded(address[] indexed implementations);

    /**
     * @dev Returns the current implementation address.
     */
    function getOzImplementations() public view returns (address[] memory) {
        return s.ozImplementations;
    }

    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newImplementation` must be a contract.
     */
    function upgradeToBeacons(address[] memory newImplementations_) public {
        LibDiamond.enforceIsContractOwner();
        _setImplementations(newImplementations_);
        emit Upgraded(newImplementations_);
    }

    /**
     * @dev Sets the implementation contract address for this beacon
     *
     * Requirements:
     *
     * - `newImplementation` must be a contract.
     */
    function _setImplementations(address[] memory newImplementations_) private {
        uint length = newImplementations_.length;

        //put here a check to see when it's upgrading one implementation only instead
        // of both in an array
        for (uint i=0; i < length; i++) {
            if (!Address.isContract(newImplementations_[i])) revert OZError24();
            s.ozImplementations.push(newImplementations_[i]);
        }
    }
}
