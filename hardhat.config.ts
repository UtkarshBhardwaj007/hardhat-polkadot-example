import { HardhatUserConfig, vars } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@parity/hardhat-polkadot';
import "@nomicfoundation/hardhat-verify";

const config: HardhatUserConfig = {
    solidity: '0.8.28',
    resolc: {
        compilerSource: 'npm',
        settings: {
            optimizer: {
              enabled: true,
              parameters: 'z',
              fallbackOz: true,
              runs: 200,
            },
            standardJson: true,
        },
    },
    networks: {
        hardhat: {
            polkavm: true,
            nodeConfig: {
                nodeBinaryPath: '/Users/utkarshbhardwaj/Desktop/Projects/UtkarshBhardwaj007/hardhat-polkadot-example/binaries/substrate-node',
                rpcPort: 8000,
                dev: true,
            },
            adapterConfig: {
                adapterBinaryPath: '/Users/utkarshbhardwaj/Desktop/Projects/UtkarshBhardwaj007/hardhat-polkadot-example/binaries/eth-rpc',
                dev: true,
            },
        },
        localNode: {
            polkavm: true,
            url: `http://127.0.0.1:8545`,
        },
        polkadotHubTestnet: {
            polkavm: true,
            url: 'https://testnet-passet-hub-eth-rpc.polkadot.io',
            accounts: vars.has('TEST_ACC_PRIVATE_KEY') ? [vars.get('TEST_ACC_PRIVATE_KEY')] : [],
        },
    }
};

export default config;
