// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/beacon/BeaconProxy.sol)

pragma solidity ^0.8.0;


import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ozIBeacon} from "./interfaces/ozIBeacon.sol";
import {ozERC1967Upgrade} from "./ozERC1967Upgrade.sol";



/**
 * @dev This contract implements a proxy that gets the implementation address for each call from an {UpgradeableBeacon}.
 *
 * The beacon address is stored in storage slot `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
 * conflict with the storage layout of the implementation behind the proxy.
 *
 * _Available since v3.4._
 */
contract ozBeaconProxy is Proxy, ozERC1967Upgrade {
    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     */
    constructor(address ozDiamond, bytes memory data, uint implIndex) {
        _upgradeBeaconToAndCall(ozDiamond, data, false, implIndex);
    }

    /**
     * @dev Returns the current beacon address.
     */
    function _beacon() internal view returns (address) {
        return _getBeacon();
    }

    function _implementation() internal view virtual override returns (address) {}

    /**
     * @dev Returns the current implementation address of the associated beacon.
     */
    function _implementations() internal view returns (address[] memory) {
        return ozIBeacon(_getBeacon()).getOzImplementations();
    }
}
