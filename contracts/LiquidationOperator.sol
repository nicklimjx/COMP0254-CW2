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
    //  returns in ETH, not native token
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

// info on user positions, use for optimiser
// https://github.com/aave/protocol-v2/tree/master/contracts/misc/interfaces
interface IProtocolDataProvider {
    // returns in native token
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

    function getReserveConfigurationData(address asset)
        external
        view
        returns (
        uint256 decimals,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        bool usageAsCollateralEnabled,
        bool borrowingEnabled,
        bool stableBorrowRateEnabled,
        bool isActive,
        bool isFrozen
        );
}

// needed for IProtocolOracle as no imports allowed
// https://github.com/aave/protocol-v2/blob/master/contracts/interfaces/IChainlinkAggregator.sol
interface IChainlinkAggregator {
  function decimals() external view returns (uint8);
  
  function latestAnswer() external view returns (int256);

  function latestTimestamp() external view returns (uint256);

  function latestRound() external view returns (uint256);

  function getAnswer(uint256 roundId) external view returns (int256);

  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);
  event NewRound(uint256 indexed roundId, address indexed startedBy);
}

// protocol oracle, used to export prices to python script
// https://github.com/aave/protocol-v2/blob/master/contracts/misc/AaveOracle.sol
interface IProtocolOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface ICurve {
}
// balancer v2
// 0% flash loan, good life, save money
interface IBPool {
    function getBalance(address token) external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
    function getSwapFee() external view returns (uint);
    function getCurrentTokens() external view returns (address[] memory);
    function getSpotPrice(address tokenIn, address tokenOut) external view returns (uint spotPrice);

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    ) external returns (uint tokenAmountOut, uint spotPriceAfter);

    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    ) external pure returns (uint tokenAmountOut);

}

// utility interfaces for IBPool, currently needed due to no imports allowed
interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
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
     **/
    function transfer(address to, uint256 value) external returns (bool);
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

contract LiquidationOperator is IFlashLoanRecipient {
    IVault private constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ILendingPool constant lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
    IProtocolOracle constant oracle = IProtocolOracle(0xA50ba011c48153De246E5192C8f9258A2ba79Ca9);

    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    //uniswap v2 stuff
    IUniswapV2Factory constant uniswapFactory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Factory constant sushiFactory = IUniswapV2Factory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);

    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;

    // set these in constructor
    address immutable WETHUSDTuni;
    address immutable WBTCUSDTuni;
    address immutable WBTCWETHuni;
    address immutable WBTCDAIuni;
    address immutable WETHDAIuni;

    address immutable WBTCWETHsushi;
    address immutable WETHDAIsushi;
    address immutable WETHUSDTsushi;
    // address immutable WBTCDAIsushi;
    // WBTCUSDTsushi did not exist at this time

    address payable private _owner;

    // helper functions
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

    function getSortedOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal pure returns(uint256 amount0Out, uint256 amount1Out){
        return tokenIn < tokenOut ? (uint256(0), amountOut) : (amountOut, uint256(0));
    }

    constructor() {
        // TODO: (optional) initialize your contract
        _owner = payable(msg.sender);
        WBTCUSDTuni = uniswapFactory.getPair(WBTC, USDT);
        WETHUSDTuni = uniswapFactory.getPair(WETH, USDT);
        WBTCWETHuni = uniswapFactory.getPair(WBTC, WETH);
        WBTCDAIuni = uniswapFactory.getPair(WBTC, DAI);
        WETHDAIuni = uniswapFactory.getPair(WETH, DAI);
        WBTCWETHsushi = sushiFactory.getPair(WBTC, WETH);
        WETHDAIsushi = sushiFactory.getPair(WETH, DAI);
        WETHUSDTsushi = sushiFactory.getPair(WETH, USDT);
        // END TODO
    }

    receive() external payable {}

    // vibe coded
    function formatUnits(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        if (amount == 0) return "0";
        
        uint256 factor = 10**decimals;
        uint256 integerPart = amount / factor;
        uint256 fractionalPart = amount % factor;
        
        // Convert fractional part to string and pad with leading zeros if necessary
        string memory fractionalStr = uintToString(fractionalPart);
        while (bytes(fractionalStr).length < decimals) {
            fractionalStr = string(abi.encodePacked("0", fractionalStr));
        }
    
        return string(abi.encodePacked(uintToString(integerPart), ".", fractionalStr));
    }

    function uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (v != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(v - (v / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            v /= 10;
        }
        return string(bstr);
    }

    function _getSolverInfo() internal view {
        (
            ,
            ,
            ,
            ,
            ,
            uint256 healthFactor
        ) = lendingPool.getUserAccountData(TARGET_USER);

        (
            uint256 wbtcCollateral,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            
        ) = dataProvider.getUserReserveData(WBTC, TARGET_USER);

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

        (
            ,
            ,
            ,
            uint256 liquidationBonus,
            ,
            ,
            ,
            ,
            ,
            
        ) = dataProvider.getReserveConfigurationData(WBTC);

        // spits out the prices relative to eth
        uint256 oracleWBTC = oracle.getAssetPrice(WBTC);
        uint256 oracleUSDT = oracle.getAssetPrice(USDT);

        uint256 totalDebt = currentStableDebt + currentVariableDebt;
        // wbtcCollateral = wbtcCollateral * 1e8 / oracleWBTC;

        // 1. get the target user account data & make sure it is liquidatable
        console.log("Liquidation bonus: %s", formatUnits(liquidationBonus, 4));

        require(healthFactor < 1e18, "Target user is not liquidatable");
        console.log("User health factor is: %s", formatUnits(healthFactor, 18));

        require(totalDebt / 2 > 0, "No debt to liquidate");
        console.log("User has USDT debt: %s", formatUnits(totalDebt, 6));
        console.log("User has WBTC collateral: %s", formatUnits(wbtcCollateral, 8));

        console.log("Oracle WBTC price: %s", formatUnits(oracleWBTC, 18));
        console.log("Oracle USDT price: %s", formatUnits(oracleUSDT, 18)); // Standardized to 18 if Chainlink

        (uint256 r0, uint256 r1) = getSortedReserves(WBTCUSDTuni, WBTC);
        console.log("Uni WBTC/USDT | WBTC: %s, USDT: %s", formatUnits(r0, 8), formatUnits(r1, 6));

        (r0, r1) = getSortedReserves(WETHUSDTuni, WETH);
        console.log("Uni WETH/USDT | WETH: %s, USDT: %s", formatUnits(r0, 18), formatUnits(r1, 6));

        (r0, r1) = getSortedReserves(WBTCWETHuni, WBTC);
        console.log("Uni WBTC/WETH | WBTC: %s, WETH: %s", formatUnits(r0, 8), formatUnits(r1, 18));

        (r0, r1) = getSortedReserves(WBTCDAIuni, WBTC);
        console.log("Uni WBTC/DAI  | WBTC: %s, DAI: %s", formatUnits(r0, 8), formatUnits(r1, 18));

        (r0, r1) = getSortedReserves(WETHDAIuni, WETH);
        console.log("Uni WETH/DAI  | WETH: %s, DAI: %s", formatUnits(r0, 18), formatUnits(r1, 18));

        // SushiSwap Pools
        (r0, r1) = getSortedReserves(WBTCWETHsushi, WBTC);
        console.log("Sushi WBTC/WETH | WBTC: %s, WETH: %s", formatUnits(r0, 8), formatUnits(r1, 18));

        (r0, r1) = getSortedReserves(WETHDAIsushi, WETH);
        console.log("Sushi WETH/DAI  | WETH: %s, DAI: %s", formatUnits(r0, 18), formatUnits(r1, 18));

        (r0, r1) = getSortedReserves(WETHUSDTsushi, WETH);
        console.log("Sushi WETH/USDT | WETH: %s, USDT: %s", formatUnits(r0, 18), formatUnits(r1, 6));
    }

    function _swapWBTCWETH(uint256 wbtcReceived) internal {
        uint256 inUni = 2929335114; 
        uint256 inSushi = wbtcReceived - inUni;
        uint256 outUni;
        uint256 outSushi;
        
        // uniswap
        (uint256 r0, uint256 r1) = getSortedReserves(WBTCWETHuni, WBTC);
        outUni = getAmountOut(inUni, r0, r1);
        (uint256 amount0Out, uint256 amount1Out) = getSortedOut(WBTC, WETH, outUni);
        
        IERC20(WBTC).transfer(WBTCWETHuni, inUni);
        IUniswapV2Pair(WBTCWETHuni).swap(amount0Out, amount1Out, address(this), bytes(""));

        // sushiswap
        (r0, r1) = getSortedReserves(WBTCWETHsushi, WBTC);
        outSushi = getAmountOut(inSushi, r0, r1);
        (amount0Out, amount1Out) = getSortedOut(WBTC, WETH, outSushi);

        IERC20(WBTC).transfer(WBTCWETHsushi, inSushi);
        IUniswapV2Pair(WBTCWETHsushi).swap(amount0Out, amount1Out, address(this), bytes(""));

        uint256 wethOut = outSushi + outUni;
        console.log("WETH from WBTC swap: %s", formatUnits(wethOut, 18));
    }

    function _swapWETHUSDT(uint256 usdtOut) internal {
        uint256 outUni = 1310806629343;
        uint256 outSushi = usdtOut - outUni; 
        uint256 inUni;
        uint256 inSushi;

        // uniswap
        (uint256 r0, uint256 r1) = getSortedReserves(WETHUSDTuni, WETH);
        inUni = getAmountIn(outUni, r0, r1);
        (uint256 amount0Out, uint256 amount1Out) = getSortedOut(WETH, USDT, outUni);
        
        IERC20(WETH).transfer(WETHUSDTuni, inUni);
        IUniswapV2Pair(WETHUSDTuni).swap(amount0Out, amount1Out, address(this), bytes(""));

        // sushiswap (Fixed pair, tokens, and math)
        (r0, r1) = getSortedReserves(WETHUSDTsushi, WETH);
        inSushi = getAmountIn(outSushi, r0, r1);
        (amount0Out, amount1Out) = getSortedOut(WETH, USDT, outSushi);

        IERC20(WETH).transfer(WETHUSDTsushi, inSushi);
        IUniswapV2Pair(WETHUSDTsushi).swap(amount0Out, amount1Out, address(this), bytes(""));

        console.log("Swapped WETH to USDT");
    }

    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData) internal {
        vault.flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == address(vault));
        IERC20(USDT).approve(address(lendingPool), amounts[0]);    // aave needs this so the contract can take the money

    // // //     // 2.1 liquidate the target user
    // // //     //    *** Your code here ***
        lendingPool.liquidationCall(
            WBTC,
            USDT,
            TARGET_USER,
            amounts[0],
            false
        );

        uint256 wbtcReceived = IERC20(WBTC).balanceOf(address(this));
        console.log("WBTC from liquidation: %s", formatUnits(wbtcReceived, 8));

        // 2.2 swap WBTC for other things or repay directly
        _swapWBTCWETH(wbtcReceived);
        _swapWETHUSDT(amounts[0]);
    //     // local variable stack space saver
    //     // _swapWBTCWETH(wbtcReceived);

        // 2.3 repay
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].transfer(address(vault), amounts[i] + feeAmounts[i]);
        }
    }

    function operate() external {
        _getSolverInfo();
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(USDT);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2916378221684;

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 0;

        bytes memory userData = "";

        makeFlashLoan(tokens, amounts, userData);
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(WETH).withdraw(wethBalance);
        }

        // // return ETH balance to caller
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = _owner.call{value:ethBalance}("");
            require(success, "ETH transfer failed");
        }
    }
}