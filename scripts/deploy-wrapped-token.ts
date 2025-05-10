import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";

async function main() {
  console.log("Compiling WrappedToken to PVM...");
  
  // First compile to PVM
  await new Promise((resolve, reject) => {
    try {
      execSync("npx hardhat compile:wasm", { stdio: 'inherit' });
      resolve(undefined);
    } catch (error) {
      reject(error);
    }
  });

  console.log("Deploying WrappedToken to Westend Asset Hub...");

  // Get the PVM bytecode
  const pvmPath = path.join(__dirname, "../artifacts-pvm/WrappedToken.flattened.sol:WrappedToken.pvm");
  const pvmBytecode = fs.readFileSync(pvmPath);

  // Get the contract factory with PVM bytecode
  const [deployer] = await ethers.getSigners();
  const factory = new ethers.ContractFactory(
    [], // ABI - empty since we're just deploying the bytecode
    "0x" + pvmBytecode.toString("hex"),
    deployer
  );
  
  // Deploy the contract
  const wrappedToken = await factory.deploy();
  await wrappedToken.waitForDeployment();

  const wrappedTokenAddress = await wrappedToken.getAddress();
  console.log("WrappedToken deployed to:", wrappedTokenAddress);

  // Save deployment info
  const deploymentsDir = path.join(__dirname, "../deployments");
  
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  fs.writeFileSync(
    path.join(deploymentsDir, "wrapped-token.json"),
    JSON.stringify({
      address: wrappedTokenAddress,
      network: "westendAssetHub",
      timestamp: new Date().toISOString()
    }, null, 2)
  );

  console.log("Deployment info saved to deployments/wrapped-token.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
