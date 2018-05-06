var token = artifacts.require("./token/ERC20/NTFToken.sol");

module.exports = function(deployer) {
  deployer.deploy(token);
};