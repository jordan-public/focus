var ProxySwap  = artifacts.require("ProxySwap");
const DAI = "0xad6d458402f60fd3bd25163575031acdce07538d";
const WETH = "0xc778417e063141139fce010982780140aa0cd5ab";

// accounts[0] = owner (of all contracts for testing purposes)
module.exports = async function(deployer, network, accounts) {
  await deployer.deploy(ProxySwap, DAI, WETH);

  console.log("ProxySwap: " + ProxySwap.address);
  console.log("Owner: "+accounts[0]);
  console.log("Demployment completed!");
};
