//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

interface IProtocolDataProvider {
    function getUserReserveData(address asset, address user)
        external
        view
        returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     * fixed this!!! usdt is so weird and doesnt allow transfers routing through
     **/
    function transfer(address to, uint256 value) external;
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function token0() external view returns (address);

    function token1() external view returns (address);
}

// ----------------------IMPLEMENTATION------------------------------

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    //    *** Your code here ***
    // aave contracts
    ILendingPool constant lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //uniswap v2 stuff
    IUniswapV2Factory constant uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;

    // set these in constructor
    address immutable WETHUSDTpair;
    address immutable WBTCWETHpair;
    address immutable WBTCUSDTpair;

    address payable private _owner;

    // END TODO

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getSortedReserves(
        address pair,
        address tokenIn
    ) internal view returns (uint112 reserveIn, uint112 reserveOut){
        IUniswapV2Pair swapPair = IUniswapV2Pair(pair);
        (uint112 r0, uint112 r1, ) = swapPair.getReserves();

        if (tokenIn == swapPair.token0()) {
            return (r0, r1);
        } else {
            return (r1, r0);
        }
    }

    constructor() {
        // TODO: (optional) initialize your contract
        _owner = payable(msg.sender);
        WETHUSDTpair = uniswapFactory.getPair(WETH, USDT);
        WBTCWETHpair = uniswapFactory.getPair(WBTC, WETH);
        WBTCUSDTpair = uniswapFactory.getPair(WBTC, USDT);
        // END TODO
    }

    // TODO: add a `receive` function so that you can withdraw your WETH
    receive() external payable {}
    // END TODO

    function _swapWBTCWETH(uint256 wbtcReceived) internal {
        (uint112 rWBTC, uint112 rWETH) = getSortedReserves(WBTCWETHpair, WBTC);
        (uint112 hoprWBTC, uint112 hoprUSDT) = getSortedReserves(WBTCUSDTpair, WBTC);
        (uint112 hoprUSDT1, uint112 hoprWETH) = getSortedReserves(WETHUSDTpair, USDT);

        uint256 bestTotalWeth = 0;
        uint256 bestDirectSplit = 0;
        
        // abuse no gas to run some basic optimiser
       
        for (uint112 i = 1; i <= 19; i++) {
            uint256 amtDirect = (wbtcReceived * i) / 20;
            uint256 amtHop = wbtcReceived - amtDirect;

            // single hop
            uint256 outDirect = getAmountOut(amtDirect, rWBTC, rWETH);

            // multi hop
            uint256 outUSDC = getAmountOut(amtHop, hoprWBTC, hoprUSDT);
            uint256 outHop = getAmountOut(outUSDC, hoprUSDT1, hoprWETH);

            if (outDirect + outHop > bestTotalWeth) {
                bestTotalWeth = outDirect + outHop;
                bestDirectSplit = amtDirect;
            }
        }

        console.log("Best direct split is: %s.%s", bestDirectSplit / 1e18, bestDirectSplit % 1e18);
        console.log("Best total WETH output is: %s.%s", bestTotalWeth / 1e18, bestTotalWeth % 1e18);

        if (bestDirectSplit > 0) {
            IERC20(WBTC).transfer(WBTCWETHpair, bestDirectSplit);
            uint256 outWethDirect = getAmountOut(bestDirectSplit, rWBTC, rWETH);

            (uint swap0, uint swap1) = (WBTC < WETH) ? (uint(0), outWethDirect) : (outWethDirect, uint(0));
            IUniswapV2Pair(WBTCWETHpair).swap(swap0, swap1, address(this), new bytes(0));
        }

        if(wbtcReceived - bestDirectSplit > 0) {
            IERC20(WBTC).transfer(WBTCUSDTpair, wbtcReceived - bestDirectSplit);
            uint256 outUSDT = getAmountOut(wbtcReceived - bestDirectSplit, hoprWBTC, hoprUSDT);

            (uint swap0, uint swap1) = (WBTC < USDT) ? (uint(0), outUSDT) : (outUSDT, uint(0));
            IUniswapV2Pair(WBTCUSDTpair).swap(swap0, swap1, address(this), new bytes(0));

            uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
            IERC20(USDT).transfer(WETHUSDTpair, usdtBalance);
            uint256 finalWethHop = getAmountOut(usdtBalance, hoprUSDT1, hoprWETH);

            (swap0, swap1) = (USDT < WETH) ? (uint(0), finalWethHop) : (finalWethHop, uint(0));
            IUniswapV2Pair(WETHUSDTpair).swap(swap0, swap1, address(this), new bytes(0));
        }

        console.log("WETH after swap: %s.%s", IERC20(WETH).balanceOf(address(this)) / 1e18, IERC20(WETH).balanceOf(address(this)) % 1e18);
    }

    function _repayFlashLoan(uint256 amountBorrowed) internal {
        IUniswapV2Pair flashPair = IUniswapV2Pair(WETHUSDTpair);
        address fToken0 = flashPair.token0();
        (uint112 fr0, uint112 fr1, ) = flashPair.getReserves();

        uint256 wethRepay;
        uint256 idealWethRepay;

        if (fToken0 == USDT) {
            wethRepay = getAmountIn(amountBorrowed, fr1, fr0);
            idealWethRepay = (amountBorrowed * fr1) / fr0;
        } else {
            wethRepay = getAmountIn(amountBorrowed, fr0, fr1);
            idealWethRepay = (amountBorrowed * fr0) / fr1;
        }

        uint256 slippageAndFees = (wethRepay - idealWethRepay);
        console.log("Ideal WETH to repay loan: %s.%s", idealWethRepay / 1e18, idealWethRepay % 1e18);
        console.log("WETH to repay flash loan: %s.%s", wethRepay / 1e18, wethRepay % 1e18);
        console.log("Slippage: %s.%s", slippageAndFees / 1e18, slippageAndFees % 1e18);
        // return;
        IERC20(WETH).transfer(WETHUSDTpair, wethRepay);
    }

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // TODO: implement your liquidation logic

        uint256 healthFactor;
        // 0. security checks and initializing variables
        (
            ,
            ,
            ,
            ,
            ,
            healthFactor
        ) = lendingPool.getUserAccountData(TARGET_USER);

        (
            ,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            ,
            ,
            ,
            ,
            ,
            
        ) = dataProvider.getUserReserveData(USDT, TARGET_USER);

        uint256 totalDebt = currentStableDebt + currentVariableDebt;

        // 1. get the target user account data & make sure it is liquidatable
        
        require(healthFactor < 1e18, "Target user is not liquidatable");   // aave returns as uint256
        console.log("User health factor is: %s.%s", healthFactor / 1e18, healthFactor % 1e18);

        require(totalDebt / 2 > 0, "No debt to liquidate");
        console.log("User has USDT debt: %s.%s", totalDebt / 1e6, totalDebt % 1e6);

        // says this at aave docs https://aave.com/help/borrowing/liquidations
        // uint256 maxLiq = totalDebt / 2;
        // debug
        uint256 maxLiq = 2916378221684;

        // if (false) {
        //     maxLiq = totalDebt;
        // } else {
        //     maxLiq = totalDebt / 2;
        // }
        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***
        IUniswapV2Pair flashPair = IUniswapV2Pair(WETHUSDTpair);
        address token0 = flashPair.token0();

        uint256 amount0Out = 0;
        uint256 amount1Out = 0;
        if (token0 == USDT) {
            amount0Out = maxLiq;
        } else {
            amount1Out = maxLiq;
        }
        
        flashPair.swap(amount0Out, amount1Out, address(this), bytes("1"));
        // because data length is mroe than 0 it calls uniSwapV2call
        // 3. Convert the profit into ETH and send back to sender
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(WETH).withdraw(wethBalance);
        }

        // return ETH balance to caller
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = _owner.call{value:ethBalance}("");
            require(success, "ETH transfer failed");
        }
        // END TODO
    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256,
        uint256 amount1,
        bytes calldata
    ) external override {
        // TODO: implement your liquidation logic
        console.log("USDT flash loaned: %s.%s", amount1 / 1e6, amount1 % 1e6);

        // 2.0. security checks and initializing variables
        // copied from uniswap docs
        assert(msg.sender == IUniswapV2Factory(uniswapFactory).getPair(
            IUniswapV2Pair(msg.sender).token0(),
            IUniswapV2Pair(msg.sender).token1()
            ));
        IERC20(USDT).approve(address(lendingPool), amount1);    // aave needs this so the contract can take the money

        // 2.1 liquidate the target user
        //    *** Your code here ***
        lendingPool.liquidationCall(
            WBTC,
            USDT,
            TARGET_USER,
            amount1,
            false
        );

        uint256 wbtcReceived = IERC20(WBTC).balanceOf(address(this));
        console.log("WBTC from liquidation: %s.%s", wbtcReceived / 1e8, wbtcReceived % 1e8);

        // 2.2 swap WBTC for other things or repay directly

        // local variable stack space saver
        _swapWBTCWETH(wbtcReceived);

        // 2.3 repay
        _repayFlashLoan(amount1);
        
        // END TODO
    }
}
