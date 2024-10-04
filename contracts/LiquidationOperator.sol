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
}


// ----------------------IMPLEMENTATION------------------------------


contract LiquidationOperator is IUniswapV2Callee {
   uint8 public constant health_factor_decimals = 18;




   // Define constants
   address public constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; // to be corrected
   address public constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
   address public constant USDT_TOKEN = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
   address public constant WBTC_TOKEN = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
   address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
   address public constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;


   // Define ILendingPool interface instance
   ILendingPool public lendingPool;


   IUniswapV2Factory public uniswapFac;



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

   constructor() {
       lendingPool = ILendingPool(AAVE_LENDING_POOL);
       uniswapFac = IUniswapV2Factory(UNISWAP_V2_FACTORY);
   }


receive() external payable {}

   function calcul(address usdt_tok, address wbtc_tok ) internal view  returns (uint256 debtToCover, uint256 wbtc_to_pay) {
       address pairAddress = uniswapFac.getPair( usdt_tok, wbtc_tok);
       (uint112 reserve_USDT, uint112 reserve_WBTC, ) = IUniswapV2Pair(pairAddress).getReserves();
       console.log("this is sthe emprunted usdt :", pairAddress );
       uint256 debtToPay = reserve_USDT;
       wbtc_to_pay = getAmountIn(debtToPay, reserve_USDT, reserve_WBTC);
       return (debtToPay, wbtc_to_pay);
   }


   // required by the testing script, entry for your liquidation call
   function operate() external {

       require(msg.sender != address(0), "Invalid sender");

       (uint256 totalCollateralETH, uint256 totalDebtETH, , , , uint256 healthFactor) = lendingPool.getUserAccountData(TARGET_USER);
       require(healthFactor < 1 ether, "User is not liquidatable");
       console.log("Total Collateral wbtc:", totalCollateralETH);
       console.log("Total totalDebt usdt :", totalDebtETH);
       console.log("healthfactor :", healthFactor);

       address pairAddress = uniswapFac.getPair(USDT_TOKEN, WBTC_TOKEN);
       IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

       uint256 count = 0;
       while (count<15){
                (uint256 debtToCover  ,uint256 debt_to_pay_wbtc) = calcul(USDT_TOKEN, WBTC_TOKEN);
                bytes memory data = abi.encode(debt_to_pay_wbtc);
                pair.swap(0,debtToCover, address(this), data);
                count = count +1 ;
       }

      uint256 collateralAmountaccount = IERC20(WBTC_TOKEN).balanceOf(address(this));

       address pairAddressWBTCWeth = uniswapFac.getPair(WBTC_TOKEN, WETH_TOKEN);


       IUniswapV2Pair pairweth= IUniswapV2Pair(pairAddressWBTCWeth);

       uint256 amountIn = collateralAmountaccount ; // 1000 WETC (assuming 18 decimals)


       (uint112 reserve0, uint112 reserve1,) = pairweth.getReserves();


       (address token0,) = WBTC_TOKEN < WETH_TOKEN ? (WBTC_TOKEN, WETH_TOKEN) : (WETH_TOKEN, WBTC_TOKEN);
       if (token0 != WBTC_TOKEN) {
             (reserve0, reserve1) = (reserve1, reserve0);
           }

           amountIn = IERC20(WBTC_TOKEN).balanceOf(address(this));
           uint256 amountOut = getAmountOut(amountIn, reserve0, reserve1);
           IERC20(WBTC_TOKEN).approve(pairAddressWBTCWeth, amountIn);
           IERC20(WBTC_TOKEN).transfer(pairAddressWBTCWeth, amountIn);

           require(amountIn > 0, "Amount to swap must be greater than zero");

           pairweth.swap( 0,amountOut, address(this),new bytes(0) );


           IWETH weth = IWETH(WETH_TOKEN);


           uint256 wethBalance = weth.balanceOf(address(this));


           weth.withdraw(wethBalance);
           payable(msg.sender).transfer(address(this).balance);

   }


   // required by the swap
   function uniswapV2Call(
       address to,
       uint256 amount0,
       uint256 debtTopay,
       bytes calldata data
   ) external override {

   // // Step 1: Security checks
   address pairAddress = uniswapFac.getPair(USDT_TOKEN, WBTC_TOKEN);
   require(msg.sender == pairAddress, "Only Uniswap pair can call");


   uint256 wbtc_to_pay = abi.decode(data, (uint256));


   IERC20(USDT_TOKEN).approve(address(lendingPool), debtTopay);

   lendingPool.liquidationCall(WBTC_TOKEN, USDT_TOKEN, TARGET_USER, debtTopay, false);

   IERC20(WBTC_TOKEN).approve(address(this), wbtc_to_pay);

   IERC20(WBTC_TOKEN).transfer(pairAddress, wbtc_to_pay);

}

}

