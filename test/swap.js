const ExchangeProxy = artifacts.require('ExchangeProxy');
const TToken = artifacts.require('TToken');
const TTokenFactory = artifacts.require('TTokenFactory');
const BFactory = artifacts.require('BFactory');
const BPool = artifacts.require('BPool');

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
      await proxy.batchSwapExactIn(swaps, WETH, DAI, toWei('2'), toWei('0'), { from: nonAdmin });
      let aBalanceEth = await pool_a.getBalance(WETH);
      let aBalanceDai = await pool_a.getBalance(DAI);

      assert.equal(fromWei(aBalanceEth), 6.5);
      assert.equal(fromWei(aBalanceDai), 1107.6923076923076924);

      let nonAdminBalanceEth = await weth.balanceOf(nonAdmin);
      let nonAdminBalanceDai = await dai.balanceOf(nonAdmin);

      assert.equal(fromWei(nonAdminBalanceEth), 48);
      assert.equal(fromWei(nonAdminBalanceDai), 10333.0159395028118396);
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
      let aBalanceEth = await pool_a.getBalance(WETH);
      let aBalanceDai = await pool_a.getBalance(DAI);

      assert.equal(fromWei(aBalanceEth), 7.145038167938931299)
      assert.equal(fromWei(aBalanceDai), 1007.6923076923076924)

      let nonAdminBalanceEth = await weth.balanceOf(nonAdmin);
      let nonAdminBalanceDai = await dai.balanceOf(nonAdmin);

      assert.equal(fromWei(nonAdminBalanceEth), 42.137704274797561871);
      assert.equal(fromWei(nonAdminBalanceDai), 11033.0159395028118396);
    });

  });

});
