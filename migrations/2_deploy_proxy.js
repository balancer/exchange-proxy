const ExchangeProxy = artifacts.require("ExchangeProxy");
const WETH9 = artifacts.require("WETH9");

module.exports = async function(deployer, network, accounts) {
    let wethAddress;
    if (network == 'development' || network == 'coverage') {
        await deployer.deploy(WETH9);
        wethAddress = WETH9.address
        deployer.deploy(ExchangeProxy, wethAddress);
    } else if (network == 'kovan-fork' || network == 'kovan') {
        wethAddress = '0xd0A1E359811322d97991E03f863a0C30C2cF029C';
        deployer.deploy(ExchangeProxy, wethAddress);
    }
    
}
