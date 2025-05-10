import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy PriceOracle
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy();
  await priceOracle.waitForDeployment();
  console.log("PriceOracle deployed to:", await priceOracle.getAddress());

  // Deploy MockERC20 for testing
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const mockToken = await MockERC20.deploy("Mock Token", "MTK");
  await mockToken.waitForDeployment();
  console.log("MockERC20 deployed to:", await mockToken.getAddress());

  // Deploy LendingPool
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.deploy();
  await lendingPool.waitForDeployment();
  console.log("LendingPool deployed to:", await lendingPool.getAddress());

  // Deploy LendingPoolBridge
  const LendingPoolBridge = await ethers.getContractFactory("LendingPoolBridge");
  const lendingPoolBridge = await LendingPoolBridge.deploy(
    await priceOracle.getAddress(),
    await lendingPool.getAddress(),
    await mockToken.getAddress()
  );
  await lendingPoolBridge.waitForDeployment();
  console.log("LendingPoolBridge deployed to:", await lendingPoolBridge.getAddress());

  // Set up initial configuration
  const tx1 = await lendingPool.transferOwnership(await lendingPoolBridge.getAddress());
  await tx1.wait();
  console.log("LendingPool ownership transferred to LendingPoolBridge");

  // Verify contracts on Etherscan
  if (process.env.ETHERSCAN_API_KEY) {
    console.log("Verifying contracts on Etherscan...");
    try {
      await hre.run("verify:verify", {
        address: await priceOracle.getAddress(),
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: await mockToken.getAddress(),
        constructorArguments: ["Mock Token", "MTK"],
      });

      await hre.run("verify:verify", {
        address: await lendingPool.getAddress(),
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: await lendingPoolBridge.getAddress(),
        constructorArguments: [
          await priceOracle.getAddress(),
          await lendingPool.getAddress(),
          await mockToken.getAddress(),
        ],
      });
    } catch (error) {
      console.error("Error verifying contracts:", error);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
