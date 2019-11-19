const ExchangeProxy = artifacts.require("ExchangeProxy");

module.exports = async function(deployer, network, accounts) {
  deployer.deploy(ExchangeProxy);
}
