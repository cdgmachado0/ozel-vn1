// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/interfaces/IERC4626Upgradeable.sol";


interface wozIToken is IERC4626Upgradeable {
    function getHello() external view;
    //------


    function wrap(uint amountIn_, address receiver_) external returns(uint);
    function unwrap(uint wozAmountIn_, address receiver_, address owner_) external;
}


