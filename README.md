# Hardhat Boilerplate for Smart Contracts on Polkadot (PassetHub)

This boilerplate project demonstrates how to use Hardhat with Polkadot Hub Testnet. It comes with a few sample contracts, Hardhat Ignition modules that deploy the contract and binaries needed for local deployment and testing. You can use this repository to simply plug in your contracts and compile, test and deploy them.

1) All binaries are in the `binaries` folder. Be sure to update the path of the binaries in the `hardhat.config.ts` file.

2) Time is returned in milliseconds in Polkadot. See the ignition module `Lock.ts`.

3) [Create a substrate account using subkey](https://paritytech.github.io/polkadot-sdk/master/subkey/index.html) (if you don't have one already): 

4) Get your private key. If you don't have your private key, you can use your mnemonic phrase to derive it. [Polkadot-Private-Key-Extractor](https://github.com/UtkarshBhardwaj007/Polkadot-Private-Key-Extractor)

5) Get Some PAS tokens from the [faucet](https://faucet.polkadot.io/?parachain=1111)

6) Commands to run this project:

```bash
git clone git@github.com:UtkarshBhardwaj007/hardhat-polkadot-example.git

npm install

npx hardhat vars set TEST_ACC_PRIVATE_KEY (your private key)

(optional) npm install --save-dev solc@<WHATEVER-VERSION-YOU-NEED> (if you need a specific solc version or you get errors regarding your solc version)

npx hardhat compile

npx hardhat ignition deploy ./ignition/modules/MyToken.ts --network polkadotHubTestnet
```

7) Commands to start a fresh project:

```bash
mkdir hardhat-example
cd hardhat-example
npm init -y
npm install --save-dev @parity/hardhat-polkadot solc@0.8.28
npm install --force @nomicfoundation/hardhat-toolbox
npx hardhat-polkadot init
npx hardhat vars set PRIVATE_KEY "INSERT_PRIVATE_KEY"
npx hardhat compile
```

Then configure the hardhat config as per documentation (linked below).

8) Resources:
- [Polkadot Smart Contracts Documentation](https://docs.polkadot.com/develop/smart-contracts/)
- [Polkadot Smart Contracts Tutorial](https://docs.polkadot.com/tutorials/smart-contracts/)
- [Polkadot Smart Contract Basics](https://docs.polkadot.com/polkadot-protocol/smart-contract-basics/)
- [BlockScout Block Explorer for PassetHub Testnet](https://blockscout-passet-hub.parity-testnet.parity.io/)
- [Remix for Polkadot](https://remix.polkadot.io/)

9) Support Channels:
- [Discord](https://discord.gg/polkadot)
- [Element/Matrix](https://matrix.to/#/#substratedevs:matrix.org)
- [Stack Exchange](https://substrate.meta.stackexchange.com/)
- [Telegram](https://t.me/substratedevs)
- [Reddit](https://www.reddit.com/r/Polkadot/)
