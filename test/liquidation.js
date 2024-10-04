const { expect } = require("chai");
const { network, ethers } = require("hardhat");
const { BigNumber, utils }  = require("ethers");
const { writeFile } = require('fs');

describe("Liquidation", function () {
  it("test", async function () {
    await network.provider.request({
        method: "hardhat_reset",
        params: [{
          forking: {
            jsonRpcUrl: "https://eth-mainnet.g.alchemy.com/v2/vlOk5VnTcM6yRX7yDw9m2-96HTBoJ5o6",
            blockNumber: 12489619,
          }
        }]
      });
    
    const gasPrice = 0;

    const accounts = await ethers.getSigners();
    const liquidator = accounts[0].address;
    addressX = "0xB597cd8D3217ea6477232F9217fa70837ff667Af";
    const code = await ethers.provider.getCode(addressX);

    console.log(code); // '0x' if it's not a contract, otherwise contract bytecode



    const beforeLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));
     
    console.log("Account Balance:", ethers.utils.formatEther(beforeLiquidationBalance), "ETH");

    const LiquidationOperator = await ethers.getContractFactory("LiquidationOperator");
    // console.log("tessssssssssssst", LiquidationOperator)

    const liquidationOperator = await LiquidationOperator.deploy(overrides = {gasPrice: gasPrice});
    console.log("Contract Address:", liquidationOperator.address);
    await liquidationOperator.deployed();       

    const liquidationTx = await liquidationOperator.operate(overrides = {gasPrice: gasPrice});
    console.log("Contract Address:", liquidationOperator.address);

    const liquidationReceipt = await liquidationTx.wait();
    console.log("Contract Deployment Block Number:", liquidationReceipt.blockNumber);

    const liquidationEvents = liquidationReceipt.logs.filter(
        v => v && v.topics && v.address === '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9' && Array.isArray(v.topics) && 
        v.topics.length > 3 && v.topics[0] === '0xe413a321e8681d831f4dbccbca790d2952b56f977908e45be37335533e005286')
        
    
    

    const expectedLiquidationEvents = liquidationReceipt.logs.filter(v => v.topics[3] === '0x00000000000000000000000059ce4a2ac5bc3f5f225439b2993b86b42f6d3e9f');
    console.log("this is the end statemetn", expectedLiquidationEvents.length)
    expect(expectedLiquidationEvents.length, "no expected liquidation").to.be.above(0);
    console.log("this is the end statemetn", expectedLiquidationEvents.length)
    expect(liquidationEvents.length, "unexpected liquidation").to.be.equal(expectedLiquidationEvents.length);

    const afterLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const profit = afterLiquidationBalance.sub(beforeLiquidationBalance);
    console.log("Profit", utils.formatEther(profit), "ETH");

    expect(profit.gt(BigNumber.from(0)), "not profitable").to.be.true;
    writeFile('profit.txt', String(utils.formatEther(profit)), function (err) {console.log("failed to write profit.txt: %s", err)});
    console.log("this is the end of the")
  });
});
