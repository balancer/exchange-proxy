const ExchangeProxy = artifacts.require('ExchangeProxy');
const TToken = artifacts.require('TToken');
const TTokenFactory = artifacts.require('TTokenFactory');
const BFactory = artifacts.require('BFactory');
const BPool = artifacts.require('BPool');
const Decimal = require('decimal.js');
const errorDelta = 10 ** -8;
const verbose = process.env.VERBOSE;

Decimal.set({ precision: 18, rounding: Decimal.ROUND_HALF_CEIL }) 

function calcRelativeDiff(_expected, _actual) {
    return Math.abs((_expected - _actual) / _expected);
}

function calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn, swapFee) {
  let weightRatio = Decimal(tokenWeightIn).div(Decimal(tokenWeightOut));
  let adjustedIn = Decimal(tokenAmountIn).times((Decimal(1).minus(Decimal(swapFee))));
  let y = Decimal(tokenBalanceIn).div(Decimal(tokenBalanceIn).plus(adjustedIn));
  let foo = y.pow(weightRatio);
  let bar = Decimal(1).minus(foo);
  let tokenAmountOut = Decimal(tokenBalanceOut).times(bar);
  return tokenAmountOut;
}

contract('ExchangeProxy', async (accounts) => {
  const admin = accounts[0];
  const nonAdmin = accounts[1];
  const toHex = web3.utils.toHex;
  const toBN = web3.utils.toBN;
  const toWei = web3.utils.toWei;
  const fromWei = web3.utils.fromWei;

  const MAX = web3.utils.toTwosComplement(-1);

  describe('Batch Swaps', () => {
    let factory;
    let proxy;
    let pool_a, pool_b, pool_c;
    let POOL_A, POOL_B, POOL_C;

    before(async () => {
      proxy = await ExchangeProxy.deployed();
      PROXY = proxy.address;
      tokens = await TTokenFactory.deployed();
      factory = await BFactory.deployed();

      await tokens.build(toHex("WETH"));
      await tokens.build(toHex("DAI"));
      await tokens.build(toHex("MKR"));

      WETH = await tokens.get.call(toHex("WETH"));
      DAI = await tokens.get.call(toHex("DAI"));
      MKR = await tokens.get.call(toHex("MKR"));
      
      weth = await TToken.at(WETH);
      dai = await TToken.at(DAI);
      mkr = await TToken.at(MKR);

      await weth.mint(toWei('50'));
      await dai.mint(toWei('10000'));
      await mkr.mint(toWei('20'));

      await weth.mint(toWei('50'), { from: nonAdmin });
      await dai.mint(toWei('10000'), { from: nonAdmin });
      await mkr.mint(toWei('20'), { from: nonAdmin });

      POOL_A = await factory.newBPool.call(); // this works fine in clean room
      await factory.newBPool();
      pool_a = await BPool.at(POOL_A);

      POOL_B = await factory.newBPool.call(); // this works fine in clean room
      await factory.newBPool();
      pool_b = await BPool.at(POOL_B);

      POOL_C = await factory.newBPool.call(); // this works fine in clean room
      await factory.newBPool();
      pool_c = await BPool.at(POOL_C);

      await weth.approve(PROXY, MAX, { from: nonAdmin });
      await dai.approve(PROXY, MAX, { from: nonAdmin });
      await mkr.approve(PROXY, MAX, { from: nonAdmin });
      
      await weth.approve(POOL_A, MAX);
      await dai.approve(POOL_A, MAX);
      await mkr.approve(POOL_A, MAX);

      await weth.approve(POOL_B, MAX);
      await dai.approve(POOL_B, MAX);
      await mkr.approve(POOL_B, MAX);

      await weth.approve(POOL_C, MAX);
      await dai.approve(POOL_C, MAX);
      await mkr.approve(POOL_C, MAX);

      await pool_a.bind(WETH, toWei('6'), toWei('5'));
      await pool_a.bind(DAI, toWei('1200'), toWei('5'));
      await pool_a.bind(MKR, toWei('2'), toWei('5'));
      await pool_a.finalize(toWei('100'));
      
      await pool_b.bind(WETH, toWei('2'), toWei('10'));
      await pool_b.bind(DAI, toWei('800'), toWei('20'));
      await pool_b.finalize(toWei('100'));

      await pool_c.bind(WETH, toWei('15'), toWei('5'));
      await pool_c.bind(DAI, toWei('2500'), toWei('5'));
      await pool_c.bind(MKR, toWei('5'), toWei('5'));
      await pool_c.finalize(toWei('100'));

    })

    it('batchSwapExactIn', async () => {
      let swaps = [
        [ 
          POOL_A,        
          toWei('0.5'),
          toWei('0'),
          MAX
        ],
        [
          POOL_B,
          toWei('0.5'),
          toWei('0'),
          MAX
        ],
        [
          POOL_C,
          toWei('1'),
          toWei('0'),
          MAX
        ]
      ]
      let totalAmountOut = await proxy.batchSwapExactIn.call(swaps, WETH, DAI, toWei('2'), toWei('0'), { from: nonAdmin });

      let pool_a_out = calcOutGivenIn(6, 5, 1200, 5, 0.5, 0);
      let pool_b_out = calcOutGivenIn(2, 10, 800, 20, 0.5, 0);
      let pool_c_out = calcOutGivenIn(15, 5, 2500, 5, 1, 0);

      console.log(pool_a_out)
      console.log(pool_b_out)
      console.log(pool_c_out)

      let expectedTotalOut = pool_a_out.plus(pool_b_out).plus(pool_c_out);

      let relDif = calcRelativeDiff(expectedTotalOut, fromWei(totalAmountOut));
      if (verbose) {
          console.log('Pool Balance');
          console.log(`expected: ${expectedTotalOut})`);
          console.log(`actual  : ${fromWei(totalAmountOut)})`);
          console.log(`relDif  : ${relDif})`);
      }

      assert.isAtMost(relDif, (errorDelta * 3));

      await proxy.batchSwapExactIn(swaps, WETH, DAI, toWei('2'), toWei('0'), { from: nonAdmin });
      
    });

    it('batchSwapExactOut', async () => {
      let swaps = [
        [ 
          POOL_A,        
          toWei('1'),
          toWei('100'),
          MAX
        ],
        [
          POOL_B,
          toWei('1'),
          toWei('100'),
          MAX
        ],
        [
          POOL_C,
          toWei('5'),
          toWei('500'),
          MAX
        ]
      ]
      await proxy.batchSwapExactOut(swaps, WETH, DAI, toWei('700'), toWei('7'), { from: nonAdmin });
      
    });

  });

});
