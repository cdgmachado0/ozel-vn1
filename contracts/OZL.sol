// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ozIDiamond} from "./interfaces/ozIDiamond.sol";
import {QuoteAsset} from "./interfaces/IOZL.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import "forge-std/console.sol";


//Add Permit to this contract
contract OZL is ERC20Upgradeable {

    using FixedPointMathLib for uint;

    address constant rEthAddr = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 private constant _OZ_DIAMOND_SLOT = bytes32(uint(keccak256('ozDiamond.storage.slot')) - 1);

    // enum QuoteAsset {
    //     USD,
    //     ETH
    // }

    constructor() {
        _disableInitializers();
    }


    function initialize(
        string memory name_, 
        string memory symbol_,
        address ozDiamond_,
        uint totalSupply_,
        uint communityAmount_
    ) external initializer {
        __ERC20_init(name_, symbol_);
        StorageSlot.getAddressSlot(_OZ_DIAMOND_SLOT).value = ozDiamond_;

        /**
         * Add here later the vesting strategy using
         * OP's VestingWallet.sol / https://medium.com/cardstack/building-a-token-vesting-contract-b368a954f99
         * Use linear distribution, not all unlocked at once.
         * When they vest, add it to circulating supply.
         */
        _mint(address(this), totalSupply_); 
        _transfer(address(this), ozDiamond_, communityAmount_);
    }



    function getBal() public view returns(uint) {
        uint bal = IERC20Permit(rEthAddr).balanceOf(address(this));
        console.log('rETH bal (from fees) ***: ', bal);

        return bal;
    }

    function getExchangeRate() external view returns(uint) {
        return this.getExchangeRate(QuoteAsset.USD);
    }


    function getExchangeRate(QuoteAsset asset_) public view returns(uint) {
        uint ONE = 1 ether;
        uint totalFeesRETH = IERC20Permit(rEthAddr).balanceOf(address(this));
        uint totalFeesQuote = _convertToQuote(asset_, totalFeesRETH);

        uint c_Supply = circulatingSupply();

        if (c_Supply == 0) return ONE;

        return ONE.mulDivDown(totalFeesQuote, c_Supply);
    }

    function _convertToQuote(QuoteAsset qt_, uint totalFeesRETH_) private view returns(uint) {
        bytes memory data = abi.encodeWithSignature('rETH_ETH()');
        data = Address.functionStaticCall(address(getOZ()), data);

        uint reth_eth = abi.decode(data, (uint));

        uint quote;

        if (qt_ == QuoteAsset.USD) {
            quote = totalFeesRETH_.mulDivDown(getOZ().rETH_USD(), 1 ether);
        } else if(qt_ == QuoteAsset.ETH) {
            quote = totalFeesRETH_.mulDivDown(reth_eth, 1 ether);
        }

        return quote;
    }


    // function redeem(uint amount_, address receiver_) external returns(uint) {
        

    // }

    // function maxRedeem(address owner) public view returns(uint256) {
    //     return balanceOf(owner);
    // }

    // function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
    //     require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

    //     uint256 assets = previewRedeem(shares);
    //     _withdraw(_msgSender(), receiver, owner, assets, shares);

    //     return assets;
    // }

    function _burn(address account, uint amount) internal override {



    }


    error AssetOutNoExist();

    // enum AssetOut {
    //     ETH,
    //     rETH
    // }

    // struct AssetOut {
    //     address ETH;
    //     address rETH
    // }

    function _triage(assetOut_) private returns(uint) {
        if (getOZ().ozTokens(assetOut_) != address(0)) return assetOut_;

        // address[] memory ethTokens = new address[](2);
        // ethTokens[0] = 
        // ethTokens[1] = rEthAddr;

        if (assetOut_ == ETH) return assetOut_;
        if (assetOut_ == rEthAddr) return assetOut_

    }


    function redeem(
        address owner_,
        address receiver_,
        address assetOut_
        uint256 ozlAmountIn_,
        uint minAmountOut_;
    ) external {
        if (
            getOZ().ozTokens(assetOut_) == address(0) &&
            assetOut != ETH &&
            assetOut != rETH
        ) revert AssetOutNoExist();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, ozlAmount_);
        }

        _burn(owner_, ozlAmount_);
        SafeERC20.safeTransfer(_asset, receiver_, assets);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares);
    }


    function _burn(address owner_, address tokenOut_, uint ozlAmountIn_, uint minAmountOut_) private returns(uint) {
        //get the OZL tokens out of the owner + send them to ozDiamond (holder of OZL dist)
        transferFrom(owner_, address(getOZ), ozlAmountIn_);

        //grabs rETH from the contract and swaps it for tokenOut_
        uint rate = getOZ().getExchangeRate();
        uint usdValue = ozlAmountIn_.mulDivDown(rate, 1 ether);
        uint rETHtoRedeem = usdValue.mulDivDown(rEthAddr, getOZ().rETH_USD()) / 1 ether;

        if (tokenOut_ == rEthAddr) return rETHtoRedeem;

        getOZ().useOZL( //<-- here *** doing the OZL-tokenOut redeem frmo treasury
            rEthAddr,
            tokenOut_,
            rETHtoRedeem,
            minAmountOut_
        );

        // _checkPauseAndSwap(
        //     rEthAddr,
        //     wethAddr,
        //     rETHtoRedeem,
        //     minAmountOut_
        //     //receipient - address(this)
        // );


        // 1 ozl --- rate in usd
        // ozlAmountIn -- usd

        // 1 rEth --- rETH_USD()
        //    x  ---- usdToRedeem

    }


    //--------

    function circulatingSupply() public view returns(uint) {
        return getOZ().getOZLCirculatingSupply();
    }

    function getOZ() public view returns(ozIDiamond) {
        return ozIDiamond(StorageSlot.getAddressSlot(_OZ_DIAMOND_SLOT).value);
    }



    


}