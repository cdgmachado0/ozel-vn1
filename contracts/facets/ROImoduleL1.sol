// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {
    AppStorage, 
    AmountsIn, 
    AmountsOut, 
    Asset,
    Action
} from "../AppStorage.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IVault, IAsset, IPool} from "../interfaces/IBalancer.sol";
import {IPool, IQueries} from "../interfaces/IBalancer.sol";
import {Helpers} from "../libraries/Helpers.sol";
import {IERC20Permit} from "../../contracts/interfaces/IERC20Permit.sol";
import {ozIDiamond} from "../interfaces/ozIDiamond.sol";
import {ozIToken} from "../interfaces/ozIToken.sol";
import {
    IRocketStorage, 
    IRocketDepositPool, 
    IRocketVault,
    IRocketDAOProtocolSettingsDeposit
} from "../interfaces/IRocketPool.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../Errors.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";



contract ROImoduleL1 {

    using TransferHelper for address;
    using FixedPointMathLib for uint;
    using Helpers for uint;
    using SafeERC20 for IERC20;
  
    AppStorage internal s;

    modifier onlyOzToken {
        if (!s.ozTokenRegistryMap[msg.sender]) revert OZError13(msg.sender);
        _;
    }


    //----------

    function useOZL(
        address tokenOut_,
        address receiver_,
        uint amountInLsd_,
        uint[] memory minAmountsOut_
    ) external returns(uint) {
        return _checkPauseAndSwap3(
            tokenOut_,
            receiver_,
            amountInLsd_,
            minAmountsOut_,
            Action.OZL_IN
        );
    }

    function _checkPauseAndSwap3(
        address tokenOut_,
        address receiver_,
        uint amountIn_,
        uint[] memory minAmountsOut_,
        Action type_
    ) private returns(uint amountOut) {
        address tokenIn;
        address tokenOut;

        if (type_ == Action.OZL_IN) {
            tokenIn = s.rETH;
            tokenOut = s.WETH;
        } 

        (bool paused,,) = IPool(s.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            amountOut = _swapUni3(
                tokenIn,
                tokenOut,
                address(this),
                amountIn_,
                minAmountsOut_[0]
            );
        } else {
            amountOut = _swapBalancer3(
                tokenIn,
                tokenOut,
                amountIn_,
                minAmountsOut_,
                Action.OZL_IN
            );
        }

        if (tokenOut_ == s.WETH) { 
            IERC20(s.WETH).safeTransfer(receiver_, amountOut);
        } else {
            amountOut = _swapUni3(
                s.WETH,
                tokenOut_,
                receiver_,
                amountOut,
                minAmountsOut_[1]
            );
        }
    }

    function _swapUni3(
        address tokenIn_,
        address tokenOut_,
        address receiver_,
        uint amountIn_, 
        uint minAmountOut_
    ) private returns(uint) {
        IERC20(tokenIn_).safeApprove(s.swapRouterUni, amountIn_);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({ 
                tokenIn: tokenIn_,
                tokenOut: tokenOut_, 
                fee: s.uniFee, 
                recipient: receiver_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: minAmountOut_.formatMinOut(tokenOut_),
                sqrtPriceLimitX96: 0
            });

        try ISwapRouter(s.swapRouterUni).exactInputSingle(params) returns(uint amountOut) { 
            return amountOut;
        } catch Error(string memory reason) {
            revert OZError01(reason);
        }
    }


    function _swapBalancer3(
        address tokenIn_, 
        address tokenOut_, 
        uint amountIn_,
        uint[] memory minAmountsOut_,
        Action type_
    ) private returns(uint amountOut) {
        
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(s.rEthWethPoolBalancer).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn_),
            assetOut: IAsset(tokenOut_),
            amount: amountIn_,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false, 
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint minOut;
        
        if (type_ == Action.OZL_IN) {
            minOut = minAmountsOut_[0]; //minAmountOutOffchain_
        } else if (type_ != Action.OZL_IN) {
            try IQueries(s.queriesBalancer).querySwap(singleSwap, funds) returns(uint minOutOnchain) {
                uint minAmountOutOffchain = minAmountsOut_[0];
                minOut = minAmountOutOffchain > minOutOnchain ? minAmountOutOffchain : minOutOnchain;

                // SafeERC20.safeApprove(IERC20(tokenIn_), vault_, singleSwap.amount);
                // amountOut = IVault(vault_).swap(singleSwap, funds, minOut, block.timestamp);
            } catch Error(string memory reason) {
                revert OZError10(reason);
            }
        }

        SafeERC20.safeApprove(IERC20(tokenIn_), s.vaultBalancer, singleSwap.amount);

        amountOut = _executeSwap(singleSwap, funds, minOut, block.timestamp);
    }


    function _executeSwap(
        IVault.SingleSwap memory singleSwap_,
        IVault.FundManagement memory funds_,
        uint minAmountOut_,
        uint blockStamp_
    ) private returns(uint) 
    {
        try IVault(s.vaultBalancer).swap(singleSwap_, funds_, minAmountOut_, blockStamp_) returns(uint amountOut) {
            if (amountOut == 0) revert OZError02();
            return amountOut;
        } catch Error(string memory reason) {
            if (Helpers.compareStrings(reason, 'BAL#507')) {
                revert OZError20();
            } else {
                revert OZError21(reason);
            }
        }
    }


    function recicleOZL(
        address owner_,
        address ozl_,
        uint amountIn_
    ) external {
        // console.log('*** in recicle ***');
        // console.log('address(this): ', address(this));
        // console.log('msg.sender: ', msg.sender);
        // console.log('---');

        // IERC20 ozl = IERC20(ozl_);

        // uint x = ozl.balanceOf(owner_);
        // console.log('ozl balance owner pre: ', x);

        // x = ozl.balanceOf(address(this));
        // console.log('ozl balance diamond pre: ', x);
        // console.log('---');

        IERC20(ozl_).safeTransferFrom(owner_, address(this), amountIn_);

        // x = ozl.balanceOf(owner_);
        // console.log('ozl balance owner post: ', x);

        // x = ozl.balanceOf(address(this));
        // console.log('ozl balance diamond post: ', x);
        // console.log('*** ***');

        ozIDiamond(address(this)).modifySupply(amountIn_);
    }



    function sendLSD(
        address lsd_, 
        address receiver_, 
        uint amount_
    ) external returns(uint) {
        console.log('## reth bal ozl - pre: ', IERC20(lsd_).balanceOf(address(this)));
        SafeERC20.safeTransfer(IERC20(lsd_), receiver_, amount_);
        console.log('## reth bal ozl - post: ', IERC20(lsd_).balanceOf(address(this)));
        return amount_;
    }



    //-------------


    function useUnderlying( 
        address underlying_, 
        address owner_,
        AmountsIn memory amounts_
    ) external onlyOzToken { 
        uint amountIn = amounts_.amountIn;
      
        underlying_.safeTransferFrom(owner_, address(this), amountIn);

        //Swaps underlying to WETH in Uniswap
        uint amountOut = _swapUni(
            underlying_, s.WETH, amountIn, amounts_.minWethOut, address(this)
        );

        if (_checkRocketCapacity(amountOut)) {
            IWETH(s.WETH).withdraw(amountOut);
            address rocketDepositPool = IRocketStorage(s.rocketPoolStorage).getAddress(s.rocketDepositPoolID); //Try here to store the depositPool with SSTORE2-3 (if it's cheaper in terms of gas) ***
            
            IRocketDepositPool(rocketDepositPool).deposit{value: amountOut}();
        } else {
            _checkPauseAndSwap(
                s.WETH, 
                s.rETH, 
                amountOut,
                amounts_.minRethOut
            );
        }
    }


    function useOzTokens(
        address owner_,
        bytes memory data_
    ) external onlyOzToken returns(uint amountOut) {
        (
            uint ozAmountIn,
            uint amountInReth,
            uint minAmountOutWeth,
            uint minAmountOutUnderlying, 
            address receiver
        ) = abi.decode(data_, (uint, uint, uint, uint, address));

        msg.sender.safeTransferFrom(owner_, address(this), ozAmountIn);

        //Swap rETH to WETH
        _checkPauseAndSwap(s.rETH, s.WETH, amountInReth, minAmountOutWeth);

        //swap WETH to underlying
        amountOut = _swapUni(
            s.WETH,
            ozIToken(msg.sender).asset(),
            IERC20Permit(s.WETH).balanceOf(address(this)),
            minAmountOutUnderlying,
            receiver
        );
    }


    //**** HELPERS */
    function _swapUni(
        address tokenIn_,
        address tokenOut_,
        uint amountIn_, 
        uint minAmountOut_, 
        address receiver_
    ) private returns(uint) {
        tokenIn_.safeApprove(s.swapRouterUni, amountIn_);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({ 
                tokenIn: tokenIn_,
                tokenOut: tokenOut_, 
                fee: s.uniFee, 
                recipient: receiver_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: minAmountOut_.formatMinOut(tokenOut_),
                sqrtPriceLimitX96: 0
            });

        try ISwapRouter(s.swapRouterUni).exactInputSingle(params) returns(uint amountOut) { 
            return amountOut;
        } catch Error(string memory reason) {
            revert OZError01(reason);
        }
    }



    
    function _swapBalancer(
        address tokenIn_, 
        address tokenOut_, 
        uint amountIn_,
        uint minAmountOutOffchain_
    ) private {
        uint amountOut;
        
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: IPool(s.rEthWethPoolBalancer).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn_),
            assetOut: IAsset(tokenOut_),
            amount: amountIn_,
            userData: new bytes(0)
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false, 
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        
        try IQueries(s.queriesBalancer).querySwap(singleSwap, funds) returns(uint minOutOnchain) {
            uint minOut = minAmountOutOffchain_ > minOutOnchain ? minAmountOutOffchain_ : minOutOnchain;

            tokenIn_.safeApprove(s.vaultBalancer, singleSwap.amount);
            amountOut = IVault(s.vaultBalancer).swap(singleSwap, funds, minOut, block.timestamp);
        } catch Error(string memory reason) {
            revert OZError10(reason);
        }
        
        if (amountOut == 0) revert OZError02();
    }


    function _checkPauseAndSwap2(
        address tokenIn_, 
        address tokenOut_, 
        address sender_,
        address receiver_,
        uint amountIn_,
        uint minAmountOut_
    ) private {
        (bool paused,,) = IPool(s.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            _swapUni(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_,
                receiver_
            );
        } else {
            // TradingLib._swapBalancer2(
            //     tokenIn_,
            //     tokenOut_,
            //     sender_,
            //     receiver_,
            //     amountIn_,
            //     minAmountOut_
            // );
        }
    }


    function _checkPauseAndSwap(
        address tokenIn_, 
        address tokenOut_, 
        uint amountIn_,
        uint minAmountOut_
    ) private {
        (bool paused,,) = IPool(s.rEthWethPoolBalancer).getPausedState(); 

        if (paused) {
            _swapUni(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_,
                address(this)
            );
        } else {
            _swapBalancer(
                tokenIn_,
                tokenOut_,
                amountIn_,
                minAmountOut_
            );
        }
    }


    function _checkRocketCapacity(uint amountIn_) private view returns(bool) {
        uint poolBalance = IRocketVault(s.rocketVault).balanceOf('rocketDepositPool');
        uint capacityNeeded = poolBalance + amountIn_;

        IRocketDAOProtocolSettingsDeposit settingsDeposit = IRocketDAOProtocolSettingsDeposit(IRocketStorage(s.rocketPoolStorage).getAddress(s.rocketDAOProtocolSettingsDepositID));
        uint maxDepositSize = settingsDeposit.getMaximumDepositPoolSize();

        return capacityNeeded < maxDepositSize;
    }   
}