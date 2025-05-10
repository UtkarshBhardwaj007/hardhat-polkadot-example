import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import * as dotenv from "dotenv";
import { spawnSync } from "child_process";
import * as fs from "fs";
import * as path from "path";

dotenv.config();

// Task to compile Solidity to PVM using resolc binary
task("compile:pvm", "Compiles contracts to PVM using resolc")
  .addParam("contract", "The name of the contract to compile")
  .setAction(async (taskArgs, hre) => {
    // First compile with local solc
    const solcPath = path.join(process.cwd(), "binaries", "solc");
    const contractPath = path.join(process.cwd(), "contracts", `${taskArgs.contract}.sol`);
    const resolcPath = path.join(process.cwd(), "binaries", "resolc");
    const pvmDir = path.join(process.cwd(), "artifacts-pvm");
    const flattenedPath = path.join(process.cwd(), "artifacts-pvm", `${taskArgs.contract}.flattened.sol`);

    // Clean and recreate PVM artifacts directory if it doesn't exist
    if (!fs.existsSync(pvmDir)) {
      fs.mkdirSync(pvmDir, { recursive: true });
    }

    try {
      // First flatten the contract
      console.log("Flattening contract...");
      const flattenedContents = await hre.run("flatten:get-flattened-sources", {
        files: [contractPath]
      });

      if (!flattenedContents) {
        throw new Error("Failed to flatten contract");
      }

      // Write flattened contract
      fs.writeFileSync(flattenedPath, flattenedContents);
      console.log("Contract flattened successfully");

      // Compile flattened contract with solc
      console.log("Compiling with solc...");
      const solcResult = spawnSync(solcPath, [
        flattenedPath,
        "--bin",
        "--abi",
        "--optimize"
      ], {
        encoding: 'utf8',
        cwd: process.cwd()
      });

      if (solcResult.status !== 0) {
        throw new Error(`solc failed: ${solcResult.stderr}`);
      }

      // Extract the binary output
      const bytecode = solcResult.stdout.split('\n')
        .find(line => line.startsWith('60'))
        ?.trim();

      if (!bytecode) {
        throw new Error('No bytecode found in solc output');
      }

      // Extract the ABI
      const abiMatch = solcResult.stdout.match(/Contract JSON ABI\n(.*)/);
      if (!abiMatch) {
        throw new Error('No ABI found in solc output');
      }

      // Create metadata JSON
      const metadata = {
        V3: {
          spec: {
            constructors: [{
              args: JSON.parse(abiMatch[1])
            }]
          }
        }
      };

      // Write metadata file
      fs.writeFileSync(
        path.join(pvmDir, `${taskArgs.contract}.flattened.sol:${taskArgs.contract}.json`),
        JSON.stringify(metadata, null, 2)
      );

      console.log("Got bytecode from solc, converting to PVM with resolc...");

      // Now use resolc to convert to PVM
      const resolcResult = spawnSync(resolcPath, [
        flattenedPath,
        "-O3",
        "--bin",
        "--output-dir",
        pvmDir,
        "--solc",
        solcPath,
        "--overwrite"
      ], {
        encoding: 'utf8',
        cwd: process.cwd(),
        env: {
          ...process.env,
          RESOLC_SKIP_SOLC: "1",
          RESOLC_SOLC: solcPath
        }
      });

      if (resolcResult.status !== 0) {
        throw new Error(`resolc failed: ${resolcResult.stderr}`);
      }

      console.log("Successfully compiled to PVM");
    } catch (error) {
      console.error("Error in compilation:", error);
      throw error;
    }
  });

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: {},
    westendAssetHub: {
      url: "https://westend-asset-hub-eth-rpc.polkadot.io",
      accounts: process.env.WESTEND_HUB_PK ? [process.env.WESTEND_HUB_PK] : [],
      chainId: 420420421
    }
  }
};

export default config;
