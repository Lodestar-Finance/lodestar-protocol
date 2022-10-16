const {
  address,
  etherMantissa
} = require('./Utils/Ethereum');

const {
  makeComptroller,
  makeCToken,
  makePriceOracle,
  makeGLPPriceOracle,
  makeMockAggregator,
  makeMockUSDAggregator,
  // makeMockFlags
} = require('./Utils/Compound');

describe('PriceOracleProxyETH', () => {
  let root, accounts;
  let oracle, backingOracle, cUsdc, cDai, cOthers, cEth, plvGLP, glp;
  // let flags;

  beforeEach(async () => {
    [root, ...accounts] = saddle.accounts;
    const comptroller = await makeComptroller();
    const mockEthUsdAggregator = await makeMockUSDAggregator({answer: 100000000000}); // ETH price of 1000 USD
    // flags = await makeMockFlags();
    cUsdc = await makeCToken({comptroller: comptroller, supportMarket: true, underlyingOpts: {decimals: 6}});
    cDai = await makeCToken({comptroller: comptroller, supportMarket: true, underlyingOpts: {decimals: 18}});
    cOthers = await makeCToken({comptroller: comptroller, supportMarket: true});
    cEth = await makeCToken({kind: "cether", comptroller: comptroller, supportMarket: true});
    plvGLP = await makeCToken({comptroller: comptroller, supportMarket: true});
    // TODO: does this need to be the GLP mock oracle instead?
    // glp = await makeCToken({comptroller: comptroller, supportMarket: true});
    glpOracle = await makeGLPPriceOracle(root);

    backingOracle = await makePriceOracle();
    // oracle = await deploy('PriceOracleProxyETH', [root, backingOracle._address, mockEthUsdAggregator._address, flags._address, cEth._address, plvGLP._address, glpOracle._address]);
    oracle = await deploy('PriceOracleProxyETH', [root, backingOracle._address, mockEthUsdAggregator._address, cEth._address, plvGLP._address, glpOracle._address]);
  });

  describe("constructor", () => {
    it("sets address of admin", async () => {
      let configuredGuardian = await call(oracle, "admin");
      expect(configuredGuardian).toEqual(root);
    });

    it("sets address of backingOracle", async () => {
      let v1PriceOracle = await call(oracle, "v1PriceOracle");
      expect(v1PriceOracle).toEqual(backingOracle._address);
    });
  });

  describe("getUnderlyingPrice", () => {
    let setPrice = async (cToken, price, base) => {
      const mockAggregator = await makeMockAggregator({answer: etherMantissa(price)});
      await send(
        oracle,
        "_setAggregators",
        [[cToken._address], [mockAggregator._address], [base]]);
    }

    let setUSDPrice = async (cToken, price, base) => {
      const mockAggregator = await makeMockUSDAggregator({answer: price});
      await send(
        oracle,
        "_setAggregators",
        [[cToken._address], [mockAggregator._address], [base]]);
    }

    let setAndVerifyBackingPrice = async (cToken, price) => {
      await send(
        backingOracle,
        "setUnderlyingPrice",
        [cToken._address, etherMantissa(price)]);

      let backingOraclePrice = await call(
        backingOracle,
        "assetPrices",
        [cToken.underlying._address]);

      expect(Number(backingOraclePrice)).toEqual(price * 1e18);
    };

    let readAndVerifyProxyPrice = async (token, price) =>{
      let proxyPrice = await call(oracle, "getUnderlyingPrice", [token._address]);
      expect(Number(proxyPrice)).toEqual(price * 1e18);
    };

    it("returns correctly for ETH base aggregator tokens", async () => {
      const price = 1;
      const base = 1; // 0: USD

      console.log('before setPrice')
      await setPrice(cUsdc, price, base);
      console.log('price is set as: ', price);
      console.log('after setPrice');
      console.log('before proxyPrice');
      let proxyPrice = await call(oracle, "getUnderlyingPrice", [cUsdc._address]);
      console.log('after proxyPrice');
      console.log('proxyPrice here', proxyPrice);
      let underlyingDecimals = await call(cUsdc.underlying, "decimals", []);
      console.log('underlyingDecimals here', underlyingDecimals);
      console.log('price & calculated price here', price, etherMantissa(price * 10**(18 - underlyingDecimals)).toFixed())
      expect(proxyPrice).toEqual(etherMantissa(price).toFixed());

      await setPrice(cDai, price, base);
      proxyPrice = await call(oracle, "getUnderlyingPrice", [cDai._address]);
      underlyingDecimals = await call(cDai.underlying, "decimals", []);
      expect(proxyPrice).toEqual(etherMantissa(price).toFixed());
    });

    it("returns correctly for USD base aggregator tokens", async () => {
      const price = 100000000; // 1 USD = 1 USD
      const base = 0; // 0: USD
      const ethUsdPrice = 100000000000;
      const aggregatorDecimals = 8;

      console.log('before setPrice')
      await setUSDPrice(cUsdc, price, base);
      console.log('price is set as: ', price);
      console.log('after setPrice');
      console.log('before proxyPrice');
      let proxyPrice = BigInt(await call(oracle, "getUnderlyingPrice", [cUsdc._address])).toString();
      console.log('after proxyPrice');
      console.log('proxyPrice here', proxyPrice);
      let underlyingDecimals = await call(cUsdc.underlying, "decimals", []);
      console.log('underlyingDecimals here', underlyingDecimals);
      console.log('price & calculated price here', price, etherMantissa(price * 10**(18 - underlyingDecimals)).toFixed());
      //let ethUsdPrice = await call(mockEthUsdAggregator, "answer");
      console.log('ethusd price is: ', ethUsdPrice);
      expect(proxyPrice).toEqual(BigInt((price * 10**(18 - aggregatorDecimals)) * (10**(18 - underlyingDecimals)) / (ethUsdPrice / 10**(aggregatorDecimals))).toString());

      await setPrice(cDai, price, base);
      proxyPrice = await call(oracle, "getUnderlyingPrice", [cDai._address]);
      underlyingDecimals = await call(cDai.underlying, "decimals", []);
      expect(proxyPrice).toEqual(BigInt((price * 10**(18 - aggregatorDecimals)) * (10**(18 - underlyingDecimals)) / (ethUsdPrice / 10**(aggregatorDecimals))).toString());
    });

    it("fallbacks to price oracle v1 if flag is raised", async () => {
      const chainlinkPrice = 1;
      const v1OraclePrice = 2;
      const base = 1; // 0: USD

      await setPrice(cOthers, chainlinkPrice, base);
      await setAndVerifyBackingPrice(cOthers, v1OraclePrice);
      let proxyPrice = await call(oracle, "getUnderlyingPrice", [cOthers._address]);
      expect(proxyPrice).toEqual(etherMantissa(chainlinkPrice).toFixed());

      await send(flags, 'setFlag', [true]);
      await expect(call(oracle, "getUnderlyingPrice", [cOthers._address])).rejects.toRevert("revert Chainlink feeds are not being updated");
    });

    it("fallbacks to price oracle v1", async () => {
      await setAndVerifyBackingPrice(cOthers, 11);
      await readAndVerifyProxyPrice(cOthers, 11);

      await setAndVerifyBackingPrice(cOthers, 37);
      await readAndVerifyProxyPrice(cOthers, 37);
    });

    it("returns 0 for token without a price", async () => {
      let unlistedToken = await makeCToken({comptroller: cUsdc.comptroller});

      await readAndVerifyProxyPrice(unlistedToken, 0);
    });
  });

  describe("_setAdmin", () => {
    it("set admin successfully", async () => {
      expect(await send(oracle, "_setAdmin", [accounts[0]])).toSucceed();
    });

    it("fails to set admin for non-admin", async () => {
      await expect(send(oracle, "_setAdmin", [accounts[0]], {from: accounts[0]})).rejects.toRevert("revert only the admin may set new admin");
    });
  });

  describe("_setGuardian", () => {
    it("set guardian successfully", async () => {
      expect(await send(oracle, "_setGuardian", [accounts[0]])).toSucceed();
    });

    it("fails to set guardian for non-admin", async () => {
      await expect(send(oracle, "_setGuardian", [accounts[0]], {from: accounts[0]})).rejects.toRevert("revert only the admin may set new guardian");
    });
  });

  describe("_setAggregators", () => {
    let mockAggregator;

    beforeEach(async () => {
      mockAggregator = await makeMockAggregator({answer: etherMantissa(1)});
    });

    it("set aggregators successfully", async () => {
      expect(await send(oracle, "_setAggregators", [[cOthers._address], [mockAggregator._address], [0]])).toSucceed(); // 0: USD
    });

    it("fails to set aggregators for non-admin", async () => {
      await expect(send(oracle, "_setAggregators", [[cOthers._address], [mockAggregator._address], [0]], {from: accounts[0]})).rejects.toRevert("revert only the admin or guardian may set the aggregators"); // 0: USD
      expect(await send(oracle, "_setGuardian", [accounts[0]])).toSucceed();
      await expect(send(oracle, "_setAggregators", [[cOthers._address], [mockAggregator._address], [0]], {from: accounts[0]})).rejects.toRevert("revert guardian may only clear the aggregator"); // 0: USD
    });

    it("fails to set aggregators for mismatched data", async () => {
      await expect(send(oracle, "_setAggregators", [[cOthers._address], [], [0]])).rejects.toRevert("revert mismatched data"); // 0: USD
      await expect(send(oracle, "_setAggregators", [[cOthers._address], [mockAggregator._address], []])).rejects.toRevert("revert mismatched data"); // 0: USD
      await expect(send(oracle, "_setAggregators", [[], [mockAggregator._address], [0]])).rejects.toRevert("revert mismatched data"); // 0: USD
    });

    it("clear aggregators successfully", async () => {
      expect(await send(oracle, "_setGuardian", [accounts[0]])).toSucceed();
      expect(await send(oracle, "_setAggregators", [[cOthers._address], [address(0)], [0]], {from: accounts[0]})).toSucceed(); // 0: USD
    });
  });
});