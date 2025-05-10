# Hardhat Lending System Example

A lending system implemented using Solidity smart contracts for Ethereum and Polkadot's Westend Asset Hub using PolkaVM.

## Features

1. Lending Pool Management
   - Deposit and withdraw assets
   - Collateral management
   - Liquidation handling

2. Variable Total Liquidity (VTL) Matching
   - Lenders specify VTL range (e.g., 1.3-1.6)
   - Borrowers specify VTL range (e.g., 1.4-1.8)
   - Efficient matching algorithm in Solidity

3. Collateral Management
   - Minimum collateral ratio: 1.4x
   - Liquidation threshold: 1.6x
   - Oracle-based price feeds
   - Automated liquidation process


Install Node.js (i.e. v22.14.0)


1. Install Dependencies:
```bash
# Clear old dependencies
rm -rf node_modules

# Install JavaScript dependencies
npm install
```

2. Resolc binary for WASM compilation:
   - Download the latest resolc binary from [Revive releases](https://github.com/paritytech/revive/releases)
   - For macOS: Download `resolc-universal-apple-darwin`
   - For Linux: Download `resolc-x86_64-unknown-linux-musl`
   - For Windows: Download `resolc-x86_64-pc-windows-msvc.exe`
   - Place the binary in the `binaries` folder and rename it to `resolc`
   - For macOS users: Run `xattr -c binaries/resolc && chmod +x binaries/resolc`

```bash
curl -L https://github.com/paritytech/revive/releases/download/v0.1.0-dev.16/resolc-universal-apple-darwin -o binaries/resolc && xattr -c binaries/resolc && chmod +x binaries/resolc
```

3. Solc binary

```bash
./scripts/download-solc.sh
```

4. Configure Environment:
Run `cp .env.example .env` and then modify the `.env` file with the following variables:
```
# Ethereum Configuration
PRIVATE_KEY=your_ethereum_private_key
SEPOLIA_URL=your_sepolia_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key  # Optional, for contract verification

# Westend Asset Hub Configuration
WESTEND_HUB_PK=your_westend_private_key  # Private key in hex format (with or without 0x prefix)
WESTEND_WRAPPED_TOKEN_ADDRESS=            # Will be set after deploying WrappedToken
```

5. PolkaVM binaries should be in the `binaries` directory from the documentation

6. Deploy Contracts:

```bash
# Clear cache
rm -rf cache-pvm artifacts-pvm
```

```bash
# Compile contracts
npx hardhat compile

# Compile contracts to WASM for Westend Asset Hub
npx hardhat compile:wasm

# First, deploy the wrapped token to Westend Asset Hub
npx hardhat run scripts/deploy-wrapped-token.ts --network westendAssetHub

# The script will:
# - Deploy the contract using PolkaVM
# - Save the contract address to deployments/wrapped-token.json

# Add the deployed address to your .env file:
WESTEND_WRAPPED_TOKEN_ADDRESS=<address_from_wrapped_token_json>

# Then deploy the lending contracts to Westend Asset Hub
npx hardhat run scripts/deploy-polkadot.ts --network westendAssetHub

# To deploy to Ethereum (optional)
npx hardhat run scripts/deploy-ethereum.ts --network sepolia
```


## Network Configuration


### Westend Asset Hub
- RPC URL: https://westend-asset-hub-eth-rpc.polkadot.io
- Chain ID: 420420421
- Currency Symbol: WND
- Block Explorer: https://blockscout-asset-hub.parity-chains-scw.parity.io


You can get test WND tokens from the [Westend Faucet](https://faucet.westend.network).

## Contract Architecture


1. `LendingPool.sol` (Ethereum)
   - Manages deposits and collateral
   - Handles liquidations
   - Tracks lender and borrower positions


2. `LendingPoolBridge.sol` (Both networks)
   - Implements matching logic
   - Manages VTL ranges
   - Handles cross-chain communication


3. `WrappedToken.sol` (Westend Asset Hub)
   - ERC20 token for cross-chain asset representation
   - Deployed using PolkaVM for Westend compatibility


## Development

### Local Development
```bash
# Start local hardhat node with PolkaVM
npx hardhat node

# Deploy to local network
npx hardhat run scripts/deploy.ts --network localNode
```


### Testing
```bash
# Run contract tests
npx hardhat test
```


### Troubleshooting

1. PolkaVM Setup
   - Ensure the eth-rpc adapter binary is in the correct location
   - Check that @parity/hardhat-polkadot is installed
   - Verify hardhat.config.ts has polkavm settings

2. Deployment Issues
   - Confirm you have sufficient WND tokens
   - Check that your private key is correctly set in .env
   - Verify network configuration in hardhat.config.ts

## License

MIT
