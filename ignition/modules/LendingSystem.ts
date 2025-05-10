import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LendingSystemModule = buildModule("LendingSystemModule", (m) => {
  // Deploy PriceOracle
  const oracle = m.contract("PriceOracle");

  // Deploy LendingPool
  const lendingPool = m.contract("LendingPool");

  // Deploy LendingPoolBridge with constructor arguments
  const lendingPoolBridge = m.contract("LendingPoolBridge", [
    oracle,
    lendingPool,
    m.getParameter("wrappedTokenAddress", "Address of the wrapped token to be used")
  ]);

  // Set PolkaVM bridge address in LendingPool
  m.call(lendingPool, "setPolkaVMBridge", [lendingPoolBridge]);

  return {
    oracle,
    lendingPool,
    lendingPoolBridge
  };
});

export default LendingSystemModule;
