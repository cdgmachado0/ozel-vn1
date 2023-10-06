// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


// import "../../lib/forge-std/src/interfaces/IERC20.sol"; 
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AppStorage} from "../AppStorage.sol";
import "solady/src/utils/FixedPointMathLib.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IRocketStorage} from "../interfaces/IRocketStorage.sol";
import {IBalancerVault, SingleSwap, SwapKind, FundManagement} from "../interfaces/IBalancerVault.sol";

import "forge-std/console.sol";




contract ROImoduleL2 {

    using TransferHelper for address;

    AppStorage internal s;

    function useUnderlying( 
        uint minAmountOut_,
        address underlying_, 
        address user_
    ) external {
        //Swaps underlying to WETH in Uniswap
        uint amountIn = IERC20(underlying_).balanceOf(address(this));
        underlying_.safeApprove(s.swapRouterUni, amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: underlying_,
                tokenOut: s.WETH, 
                fee: 500, //make this a programatic value
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut_, 
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(s.swapRouterUni).exactInputSingle(params);

        //Swaps WETH to rETH 

        // convert ETH/WETH to rETH - rocketPool

    }


    //**** HELPERS */

    /**
     * add a fallback oracle like uni's TWAP
     **** handle the possibility with Chainlink of Sequencer being down (https://docs.chain.link/data-feeds/l2-sequencer-feeds)
     */
    // function _calculateMinOut(uint erc20Balance_) private view returns(uint minOut) {
    //     (,int price,,,) = AggregatorV3Interface(s.ethUsdChainlink).latestRoundData();
    //     uint expectedOut = erc20Balance_.fullMulDiv(uint(price) * 10 ** 10, 1 ether);
    //     uint minOutUnprocessed = 
    //         expectedOut - expectedOut.fullMulDiv(s.defaultSlippage * 100, 1000000); 
    //     minOut = minOutUnprocessed.mulWad(10 ** 6);
    // }

    // function changeETHUSDfeed() external {}

}