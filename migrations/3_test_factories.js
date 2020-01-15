const TTokenFactory = artifacts.require("TTokenFactory");
const BFactory = artifacts.require("BFactory");
const WETH9 = artifacts.require("WETH9");

module.exports = async function(deployer, network, accounts) {
  if (network == 'development' || network == 'coverage') {
    deployer.deploy(TTokenFactory);
    deployer.deploy(BFactory);
    deployer.deploy(WETH9);
  }
}
