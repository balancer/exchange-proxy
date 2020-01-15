const Decimal = require('decimal.js');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');

const ExchangeProxy = artifacts.require('ExchangeProxy');
const TToken = artifacts.require('TToken');
const TTokenFactory = artifacts.require('TTokenFactory');
const BFactory = artifacts.require('BFactory');
const BPool = artifacts.require('BPool');
const Weth9 = artifacts.require('WETH9');
const errorDelta = 10 ** -8;
const verbose = process.env.VERBOSE;

contract('ExchangeProxy', async (accounts) => {
    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const { toHex } = web3.utils;
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    describe('Batch Swaps', () => {
        let factory;
        let proxy; let PROXY;
        let tokens;
        let pool1; let pool2; let pool3;
        let POOL1; let POOL2; let POOL3;
        let weth; let dai; let mkr;
        let WETH; let DAI; let MKR;

        before(async () => {
            proxy = await ExchangeProxy.deployed();
            PROXY = proxy.address;
            tokens = await TTokenFactory.deployed();
            factory = await BFactory.deployed();
            weth = await Weth9.deployed();
            WETH = weth.address;
            
            await tokens.build(toHex('DAI'), toHex('DAI'), 18);
            await tokens.build(toHex('MKR'), toHex('MKR'), 18);

            DAI = await tokens.get.call(toHex('DAI'));
            MKR = await tokens.get.call(toHex('MKR'));

            dai = await TToken.at(DAI);
            mkr = await TToken.at(MKR);

            await weth.deposit({ value: toWei('50')});
            await dai.mint(admin, toWei('10000'));
            await mkr.mint(admin, toWei('20'));

            await weth.deposit({ from: nonAdmin, value: toWei('50')});
            await dai.mint(nonAdmin, toWei('10000'));
            await mkr.mint(nonAdmin, toWei('20'));

            POOL1 = await factory.newBPool.call(); // this works fine in clean room
            await factory.newBPool();
            pool1 = await BPool.at(POOL1);

            POOL2 = await factory.newBPool.call(); // this works fine in clean room
            await factory.newBPool();
            pool2 = await BPool.at(POOL2);

            POOL3 = await factory.newBPool.call(); // this works fine in clean room
            await factory.newBPool();
            pool3 = await BPool.at(POOL3);

            await weth.approve(PROXY, MAX, { from: nonAdmin });
            await dai.approve(PROXY, MAX, { from: nonAdmin });
            await mkr.approve(PROXY, MAX, { from: nonAdmin });

            await weth.approve(POOL1, MAX);
            await dai.approve(POOL1, MAX);
            await mkr.approve(POOL1, MAX);

            await weth.approve(POOL2, MAX);
            await dai.approve(POOL2, MAX);
            await mkr.approve(POOL2, MAX);

            await weth.approve(POOL3, MAX);
            await dai.approve(POOL3, MAX);
            await mkr.approve(POOL3, MAX);

            await pool1.bind(WETH, toWei('6'), toWei('5'));
            await pool1.bind(DAI, toWei('1200'), toWei('5'));
            await pool1.bind(MKR, toWei('2'), toWei('5'));
            await pool1.finalize(toWei('100'));

            await pool2.bind(WETH, toWei('2'), toWei('10'));
            await pool2.bind(DAI, toWei('800'), toWei('20'));
            await pool2.finalize(toWei('100'));

            await pool3.bind(WETH, toWei('15'), toWei('5'));
            await pool3.bind(DAI, toWei('2500'), toWei('5'));
            await pool3.bind(MKR, toWei('5'), toWei('5'));
            await pool3.finalize(toWei('100'));
        });

        it('batchSwapExactIn dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('1'),
                    toWei('0'),
                    MAX,
                ],
            ];
            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountOut = await proxy.batchSwapExactIn.call(
                swaps, WETH, DAI, toWei('2'), toWei('0'),
                { from: nonAdmin },
            );

            const pool1Out = calcOutGivenIn(6, 5, 1200, 5, 0.5, swapFee);
            const pool2Out = calcOutGivenIn(2, 10, 800, 20, 0.5, swapFee);
            const pool3Out = calcOutGivenIn(15, 5, 2500, 5, 1, swapFee);

            const expectedTotalOut = pool1Out.plus(pool2Out).plus(pool3Out);

            const relDif = calcRelativeDiff(expectedTotalOut, Decimal(fromWei(totalAmountOut)));

            if (verbose) {
                console.log('Pool Balance');
                console.log(`expected: ${expectedTotalOut})`);
                console.log(`actual  : ${fromWei(totalAmountOut)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchSwapExactOut dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('5'),
                    toWei('500'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountIn = await proxy.batchSwapExactOut.call(
                swaps, WETH, DAI, toWei('700'), toWei('7'),
                { from: nonAdmin },
            );

            const pool1In = calcInGivenOut(6, 5, 1200, 5, 100, swapFee);
            const pool2In = calcInGivenOut(2, 10, 800, 20, 100, swapFee);
            const pool3In = calcInGivenOut(15, 5, 2500, 5, 500, swapFee);

            const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

            const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
            if (verbose) {
                console.log('Pool Balance');
                console.log(`expected: ${expectedTotalIn})`);
                console.log(`actual  : ${fromWei(totalAmountIn)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });
    });
});
