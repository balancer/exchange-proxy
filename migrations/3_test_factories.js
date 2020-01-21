const TTokenFactory = artifacts.require("TTokenFactory");
const BFactory = artifacts.require("BFactory");

module.exports = async function(deployer, network, accounts) {
    if (network == 'development' || network == 'coverage') {
        deployer.deploy(TTokenFactory);
        deployer.deploy(BFactory);
    }
}
