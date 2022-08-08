const { assert } = require("chai");

const vRouter = artifacts.require("vRouter");
const vPair = artifacts.require("vPair");
const vPairFactory = artifacts.require("vPairFactory");
const vSwapLibrary = artifacts.require("vSwapLibrary");
const exchangeReserves = artifacts.require("exchangeReserves");

const ERC20 = artifacts.require("ERC20PresetFixedSupply");
const {
  getEncodedSwapData,
  getEncodedExchangeReserveCallbackParams,
} = require("./utils");

contract("exchangeReserves", (accounts) => {
  function fromWeiToNumber(number) {
    return parseFloat(web3.utils.fromWei(number, "ether")).toFixed(6) * 1;
  }

  async function getFutureBlockTimestamp() {
    const blockNumber = await web3.eth.getBlockNumber();
    const block = await web3.eth.getBlock(blockNumber);
    return block.timestamp + 1000000;
  }

  const A_PRICE = 1;
  const B_PRICE = 3;
  const C_PRICE = 6;
  const D_PRICE = 10;

  let tokenA, tokenB, tokenC, WETH;

  const issueAmount = web3.utils.toWei("100000000000000", "ether");

  let vPairFactoryInstance, vRouterInstance, vExchangeReserves;

  before(async () => {
    tokenA = await ERC20.new("tokenA", "A", issueAmount, accounts[0]);

    tokenB = await ERC20.new("tokenB", "B", issueAmount, accounts[0]);

    tokenC = await ERC20.new("tokenC", "C", issueAmount, accounts[0]);

    tokenD = await ERC20.new("tokenD", "D", issueAmount, accounts[0]);

    vPairFactoryInstance = await vPairFactory.deployed();
    vRouterInstance = await vRouter.deployed();
    vSwapLibraryInstance = await vSwapLibrary.deployed();
    vExchangeReserves = await exchangeReserves.deployed();

    tokenA.transfer(
      vExchangeReserves.address,
      web3.utils.toWei("10000", "ether")
    );
    tokenB.transfer(
      vExchangeReserves.address,
      web3.utils.toWei("10000", "ether")
    );

    tokenC.transfer(
      vExchangeReserves.address,
      web3.utils.toWei("10000", "ether")
    );
    tokenD.transfer(
      vExchangeReserves.address,
      web3.utils.toWei("10000", "ether")
    );

    await tokenA.approve(vRouterInstance.address, issueAmount);
    await tokenB.approve(vRouterInstance.address, issueAmount);
    await tokenC.approve(vRouterInstance.address, issueAmount);
    await tokenD.approve(vRouterInstance.address, issueAmount);

    await vPairFactoryInstance.setExchangeReservesAddress(
      exchangeReserves.address
    );

    const futureTs = await getFutureBlockTimestamp();

    //create pool A/B with 10,000 A and equivalent B
    let AInput = 10000 * A_PRICE;
    let BInput = (B_PRICE / A_PRICE) * AInput;

    await vRouterInstance.addLiquidity(
      tokenA.address,
      tokenB.address,
      web3.utils.toWei(AInput.toString(), "ether"),
      web3.utils.toWei(BInput.toString(), "ether"),
      web3.utils.toWei(AInput.toString(), "ether"),
      web3.utils.toWei(BInput.toString(), "ether"),
      accounts[0],
      futureTs
    );

    //create pool A/C
    //create pool A/B with 10,000 A and equivalent C

    let CInput = (C_PRICE / A_PRICE) * AInput;
    await vRouterInstance.addLiquidity(
      tokenA.address,
      tokenC.address,
      web3.utils.toWei(AInput.toString(), "ether"),
      web3.utils.toWei(CInput.toString(), "ether"),
      web3.utils.toWei(AInput.toString(), "ether"),
      web3.utils.toWei(CInput.toString(), "ether"),
      accounts[0],
      futureTs
    );

    //create pool B/C
    //create pool B/C with 10,000 B and equivalent C
    BInput = 20000 * B_PRICE;
    CInput = (C_PRICE / B_PRICE) * BInput;
    await vRouterInstance.addLiquidity(
      tokenB.address,
      tokenC.address,
      web3.utils.toWei(BInput.toString(), "ether"),
      web3.utils.toWei(CInput.toString(), "ether"),
      web3.utils.toWei(BInput.toString(), "ether"),
      web3.utils.toWei(CInput.toString(), "ether"),
      accounts[0],
      futureTs
    );

    //create pool B/D
    //create pool B/D with 10,000 B and equivalent C
    BInput = 50000 * B_PRICE;
    let DInput = (D_PRICE / B_PRICE) * BInput;
    await vRouterInstance.addLiquidity(
      tokenB.address,
      tokenD.address,
      web3.utils.toWei(BInput.toString(), "ether"),
      web3.utils.toWei(DInput.toString(), "ether"),
      web3.utils.toWei(BInput.toString(), "ether"),
      web3.utils.toWei(DInput.toString(), "ether"),
      accounts[0],
      futureTs
    );

    //whitelist tokens in pools

    //pool 1
    const address = await vPairFactoryInstance.getPair(
      tokenA.address,
      tokenB.address
    );
    const pool = await vPair.at(address);

    //whitelist token C
    await pool.setWhitelist([tokenC.address, tokenD.address]);

    let reserve0 = await pool.reserve0();
    let reserve1 = await pool.reserve1();

    reserve0 = fromWeiToNumber(reserve0);
    reserve1 = fromWeiToNumber(reserve1);

    // console.log("pool1: A/B: " + reserve0 + "/" + reserve1);

    //pool 2
    const address2 = await vPairFactoryInstance.getPair(
      tokenA.address,
      tokenC.address
    );
    const pool2 = await vPair.at(address2);

    //whitelist token B
    await pool2.setWhitelist([tokenB.address, tokenD.address]);

    let reserve0Pool2 = await pool2.reserve0();
    let reserve1Pool2 = await pool2.reserve1();

    reserve0Pool2 = fromWeiToNumber(reserve0Pool2);
    reserve1Pool2 = fromWeiToNumber(reserve1Pool2);

    // console.log("pool2: A/C: " + reserve0Pool2 + "/" + reserve1Pool2);

    //pool 3
    const address3 = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenC.address
    );
    const pool3 = await vPair.at(address3);

    //whitelist token A
    await pool3.setWhitelist([tokenA.address, tokenD.address]);

    let reserve0Pool3 = await pool3.reserve0();
    let reserve1Pool3 = await pool3.reserve1();

    reserve0Pool3 = fromWeiToNumber(reserve0Pool3);
    reserve1Pool3 = fromWeiToNumber(reserve1Pool3);

    // console.log("pool3: B/C: " + reserve0Pool3 + "/" + reserve1Pool3);

    //pool 4
    const address4 = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenD.address
    );
    const pool4 = await vPair.at(address4);

    //whitelist token A
    await pool4.setWhitelist([tokenA.address, tokenC.address]);

    let reserve0Pool4 = await pool4.reserve0();
    let reserve1Pool4 = await pool4.reserve1();

    reserve0Pool4 = fromWeiToNumber(reserve0Pool4);
    reserve1Pool4 = fromWeiToNumber(reserve1Pool4);

    // console.log("pool4: B/D: " + reserve0Pool4 + "/" + reserve1Pool4);
  });

  it("Should add C to pool A/B", async () => {
    const ikPair = await vPairFactoryInstance.getPair(
      tokenC.address,
      tokenB.address
    );

    const jkPair = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenA.address
    );

    const pool = await vPair.at(jkPair);

    let amountOut = web3.utils.toWei("10", "ether");

    let amountIn = await vRouterInstance.getVirtualAmountIn(
      jkPair,
      ikPair,
      amountOut
    );

    let reserveRatioBefore = await pool.calculateReserveRatio();
    let tokenCReserve = await pool.reservesBaseValue(tokenC.address);

    //Conversion errors of weiToNumber
    amountIn = web3.utils.toWei(
      (fromWeiToNumber(amountIn.toString()) * 1.001).toFixed(5),
      "ether"
    );

    let data = getEncodedSwapData(
      accounts[0],
      tokenC.address,
      tokenA.address,
      tokenB.address,
      amountIn
    );

    const futureTs = await getFutureBlockTimestamp();

    await vRouterInstance.swapReserveToExactNative(
      tokenA.address,
      tokenB.address,
      ikPair,
      amountOut,
      accounts[0],
      data,
      futureTs
    );

    let reserveRatioAfter = await pool.calculateReserveRatio();

    expect(fromWeiToNumber(reserveRatioBefore)).to.lessThan(
      fromWeiToNumber(reserveRatioAfter)
    );

    let tokenCReserveAfter = await pool.reservesBaseValue(tokenC.address);
    expect(fromWeiToNumber(tokenCReserve)).to.lessThan(
      fromWeiToNumber(tokenCReserveAfter)
    );
  });

  it("Should add A to pool B/C", async () => {
    const ikPair = await vPairFactoryInstance.getPair(
      tokenA.address,
      tokenB.address
    );

    const jkPair = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenC.address
    );

    const pool = await vPair.at(jkPair);

    let amountOut = web3.utils.toWei("10", "ether");

    let amountIn = await vRouterInstance.getVirtualAmountIn(
      jkPair,
      ikPair,
      amountOut
    );

    let reserveRatioBefore = await pool.calculateReserveRatio();
    let tokenAReserve = await pool.reservesBaseValue(tokenA.address);

    //Conversion errors of weiToNumber
    amountIn = web3.utils.toWei(
      (fromWeiToNumber(amountIn.toString()) * 1.001).toFixed(5),
      "ether"
    );

    let data = getEncodedSwapData(
      accounts[0],
      tokenA.address,
      tokenB.address,
      tokenC.address,
      amountIn
    );

    const futureTs = await getFutureBlockTimestamp();

    await vRouterInstance.swapReserveToExactNative(
      tokenB.address,
      tokenC.address,
      ikPair,
      amountOut,
      accounts[0],
      data,
      futureTs
    );

    let reserveRatioAfter = await pool.calculateReserveRatio();

    expect(fromWeiToNumber(reserveRatioBefore)).to.lessThan(
      fromWeiToNumber(reserveRatioAfter)
    );

    let tokenAReserveAfter = await pool.reservesBaseValue(tokenA.address);
    expect(fromWeiToNumber(tokenAReserve)).to.lessThan(
      fromWeiToNumber(tokenAReserveAfter)
    );
  });

  it("Should exchange reserves A<>C -> A goes from B/C to A/B, C goes from A/B to B/C", async () => {
    //get amount of A in pool B/C
    const poolABAddress = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenA.address
    );

    const poolBCAddress = await vPairFactoryInstance.getPair(
      tokenB.address,
      tokenC.address
    );

    const poolAB = await vPair.at(poolABAddress);
    const poolBC = await vPair.at(poolBCAddress);

    let amountAInReserve = await poolBC.reserves(tokenA.address);

    let data = getEncodedExchangeReserveCallbackParams(
      poolBCAddress, //jk1
      poolABAddress, //jk2
      poolBCAddress //ik2
    );

    await tokenC.transfer(poolBCAddress, web3.utils.toWei("100", "ether"));

    let aReserveInBC = await poolBC.reserves(tokenA.address);
    let cReserveInAB = await poolAB.reserves(tokenC.address);
    let poolABRR = await poolAB.calculateReserveRatio();

    let tokenAReserveBaseValue = await poolBC.reservesBaseValue(tokenA.address);
    let tokenCReserveBaseValue = await poolAB.reservesBaseValue(tokenC.address);

    let poolBCRR = await poolBC.calculateReserveRatio();

    //get flash swap of amount required amount C from pool BC.
    await vExchangeReserves.exchange(
      poolBCAddress, //jk1
      poolABAddress, // ik1
      poolABAddress, //jk2
      amountAInReserve,
      data
    );

    let tokenAReserveBaseValueAfter = await poolBC.reservesBaseValue(
      tokenA.address
    );
    let tokenCReserveBaseValueAfter = await poolAB.reservesBaseValue(
      tokenC.address
    );

    let aReserveInBCAfter = await poolBC.reserves(tokenA.address);
    let cReserveInABAfter = await poolAB.reserves(tokenC.address);
    let poolABRRAfter = await poolAB.calculateReserveRatio();

    let poolBCRRAfter = await poolBC.calculateReserveRatio();

    assert.equal(aReserveInBCAfter, 0);

    expect(fromWeiToNumber(poolABRRAfter)).to.lessThan(
      fromWeiToNumber(poolABRR)
    );

    expect(fromWeiToNumber(poolBCRRAfter)).to.lessThan(
      fromWeiToNumber(poolBCRR)
    );

    expect(fromWeiToNumber(tokenAReserveBaseValueAfter)).to.lessThan(
      fromWeiToNumber(tokenAReserveBaseValue)
    );

    expect(fromWeiToNumber(aReserveInBCAfter)).to.lessThan(
      fromWeiToNumber(aReserveInBC)
    );

    expect(fromWeiToNumber(cReserveInABAfter)).to.lessThan(
      fromWeiToNumber(cReserveInAB)
    );
  });
});
