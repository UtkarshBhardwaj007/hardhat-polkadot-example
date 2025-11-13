# 🤖 Dynamic Task Automation System on Polkadot

A decentralized automation marketplace built on **Polkadot (PassetHub Testnet)** that enables users to create dynamic, composable tasks that can interact with **any DeFi protocol** (Uniswap, Aave, Curve, etc.). Executors earn rewards for completing these tasks.

## 🎯 Key Features

### ✨ **Dynamic Task Creation**
- Create tasks that call **any smart contract** (not limited to predefined types)
- Compose **multi-step workflows** (e.g., claim rewards → swap → deposit)
- No contract upgrades needed for new protocols

### 🔗 **Protocol Agnostic**
- Built-in adapters for Uniswap, Aave, Compound, Curve
- Easy to add new protocol adapters
- Whitelist mode for security

### 💰 **Executor Marketplace**
- Anyone can register as an executor
- Earn rewards for completing tasks
- Reputation system with tiered benefits (Rookie → Diamond)

### 🛡️ **Secure & Trustless**
- Escrow-based payments
- Condition validation before execution
- Execution locks prevent front-running
- Platform fee (1% default)

---

## 📦 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  USER CREATES TASK                           │
│  Condition: "ETH price >= $3000"                            │
│  Actions: ["Swap 1 ETH for USDC on Uniswap"]               │
│  Reward: 0.5 GLMR                                           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              DYNAMICTASKREGISTRY.sol                         │
│  • Stores task definition on-chain                          │
│  • Locks reward in PaymentEscrow                            │
│  • Validates protocols are approved                         │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│             EXECUTOR DISCOVERS & EXECUTES                    │
│  ExecutorManager → Lock task for 30s                        │
│  ConditionChecker → Verify ETH price >= $3000               │
│  ActionRouter → Route to UniswapAdapter                     │
│  UniswapAdapter → Execute swap on Uniswap                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│               REWARD DISTRIBUTION                            │
│  PaymentEscrow → Release 0.495 GLMR to executor            │
│               → Send 0.005 GLMR platform fee               │
│  ReputationSystem → Increase executor reputation            │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Smart Contracts

### Core Contracts

| Contract | Purpose | Key Functions |
|----------|---------|---------------|
| **DynamicTaskRegistry.sol** | Main task registry | `createTask()`, `executeTask()`, `cancelTask()` |
| **ConditionChecker.sol** | Validates execution conditions | `checkCondition()` for price, time, balance |
| **ActionRouter.sol** | Routes actions to protocols | `routeAction()`, `registerAdapter()` |
| **PaymentEscrow.sol** | Holds rewards in escrow | `lockFunds()`, `releasePayment()` |
| **ExecutorManager.sol** | Manages executors | `registerExecutor()`, `attemptExecute()` |
| **ReputationSystem.sol** | Tracks executor reputation | `recordSuccess()`, `calculateRewardWithMultiplier()` |

### Protocol Adapters

| Adapter | Protocol | Supported Actions |
|---------|----------|-------------------|
| **UniswapLimitOrderAdapter.sol** | Uniswap V2 forks | Limit order swaps |

---

## 🚀 Quick Start

### 1. Installation

```bash
# Clone repository
cd hardhat-polkadot-example

# Install dependencies
npm install

# Setup environment variables
cp .env.example .env
# Edit .env with your private key and endpoints
```

### 2. Compile Contracts

```bash
npx hardhat compile
```

### 3. Run Tests

```bash
npx hardhat test
```

### 4. Deploy to PassetHub Testnet

```bash
npx hardhat ignition deploy ignition/modules/TaskAutomationSystem.ts --network polkadotHubTestnet
```

This will deploy all contracts and configure them automatically.

**Save the deployed addresses** from `ignition/deployments/<chain-id>/deployed_addresses.json`

### 5. Setup Environment Variables

After deployment, update your `.env`:

```env
TASK_REGISTRY_ADDRESS=0x...
EXECUTOR_MANAGER_ADDRESS=0x...
ACTION_ROUTER_ADDRESS=0x...
UNISWAP_ADAPTER_ADDRESS=0x...

# DEX Router on Moonbeam (e.g., StellaSwap)
UNISWAP_ROUTER=0x70085a09D30D6f8C4ecF6eE10120d1847383BB57

# Example tokens on Moonbeam
TOKEN_IN=0x931715FEE2d06333043d11F658C8CE934aC61D0c  # USDC
TOKEN_OUT=0xAcc15dC74880C9944775448304B263D191c6077F # WGLMR
```

### 6. Create Your First Task

```bash
npx hardhat run scripts/interactLimitOrder.ts --network polkadotHubTestnet
```

---

## 💻 Usage Examples

### Example 1: Simple Limit Order

```typescript
import { ethers } from "hardhat";

// Connect to TaskRegistry
const taskRegistry = await ethers.getContractAt(
  "DynamicTaskRegistry",
  TASK_REGISTRY_ADDRESS
);

// Define condition (ALWAYS = execute immediately if price is good)
const condition = {
  conditionType: 0, // ALWAYS
  conditionData: "0x",
};

// Define action (swap on Uniswap)
const actionParams = ethers.AbiCoder.defaultAbiCoder().encode(
  ["address", "address", "uint256", "uint256", "address", "address"],
  [
    TOKEN_IN,        // USDC
    TOKEN_OUT,       // WGLMR
    AMOUNT_IN,       // 100 USDC
    MIN_AMOUNT_OUT,  // Min 10 WGLMR
    user.address,    // Recipient
    user.address,    // Token owner
  ]
);

const action = {
  protocol: UNISWAP_ROUTER,
  selector: "0x38ed1739", // swapExactTokensForTokens
  params: actionParams,
  value: 0,
};

// Create task
const tx = await taskRegistry.createTask(
  condition,
  [action],
  ethers.parseEther("0.25"), // 0.25 GLMR reward
  0,  // No expiry
  1,  // One-time execution
  0,  // No recurring
  { value: ethers.parseEther("0.25") }
);

const receipt = await tx.wait();
console.log("Task created!");
```

### Example 2: Recurring DCA Task

```typescript
// DCA: Buy $100 USDC → ETH every 7 days for 52 weeks

const condition = {
  conditionType: 0, // ALWAYS (will check interval in task config)
  conditionData: "0x",
};

const action = {
  protocol: UNISWAP_ROUTER,
  selector: "0x38ed1739",
  params: encodedSwapParams,
  value: 0,
};

const reward = ethers.parseEther("0.25");
const executions = 52; // 52 weeks
const interval = 7 * 24 * 60 * 60; // 7 days in seconds

await taskRegistry.createTask(
  condition,
  [action],
  reward,
  0,             // No expiry
  executions,    // 52 executions
  interval,      // Execute every 7 days
  { value: reward * BigInt(executions) } // Fund all 52 executions
);
```

### Example 3: Multi-Step Workflow

```typescript
// Claim Aave rewards → Swap to USDC → Send 50% to Alice, 50% to Bob

const actions = [
  {
    protocol: AAVE_POOL,
    selector: "0x...", // claimRewards
    params: encodeClaimParams(),
    value: 0,
  },
  {
    protocol: UNISWAP_ROUTER,
    selector: "0x38ed1739", // swap
    params: encodeSwapParams(),
    value: 0,
  },
  {
    protocol: USDC_TOKEN,
    selector: "0xa9059cbb", // transfer
    params: encodeTransferParams(alice, amount / 2),
    value: 0,
  },
  {
    protocol: USDC_TOKEN,
    selector: "0xa9059cbb", // transfer
    params: encodeTransferParams(bob, amount / 2),
    value: 0,
  },
];

await taskRegistry.createTask(
  condition,
  actions, // Multiple actions executed sequentially
  ethers.parseEther("1"), // Higher reward for complex task
  0,
  1,
  0,
  { value: ethers.parseEther("1") }
);
```

---

## 🎮 Executor Guide

### Register as Executor

```typescript
const executorManager = await ethers.getContractAt(
  "ExecutorManager",
  EXECUTOR_MANAGER_ADDRESS
);

await executorManager.registerExecutor();
console.log("Registered as executor!");
```

### Execute Tasks

```typescript
// Get executable tasks
const tasks = await taskRegistry.getExecutableTasks(10);

// Execute task
for (const task of tasks) {
  try {
    const tx = await executorManager.attemptExecute(task.id);
    await tx.wait();
    console.log(`Executed task ${task.id}, earned ${task.reward} GLMR`);
  } catch (error) {
    console.log(`Failed to execute task ${task.id}`);
  }
}
```

### Check Your Stats

```typescript
const stats = await executorManager.getExecutor(executor.address);
console.log(`Total executions: ${stats.totalExecutions}`);
console.log(`Success rate: ${stats.successfulExecutions / stats.totalExecutions * 100}%`);

const reputation = await reputationSystem.getReputation(executor.address);
console.log(`Reputation score: ${reputation.reputationScore}`);
console.log(`Tier: ${reputation.tier}`); // 0=Rookie, 1=Bronze, 2=Silver, 3=Gold, 4=Diamond
```

---

## 🔧 Condition Types

| Type | Code | Description | Parameters |
|------|------|-------------|------------|
| **ALWAYS** | `0` | Always executable | None |
| **PRICE_THRESHOLD** | `1` | Asset price >= or <= target | `(token, targetPrice, isGreaterThan)` |
| **TIME_BASED** | `2` | Execute after timestamp | `(targetTimestamp)` |
| **BALANCE_THRESHOLD** | `3` | Balance >= or <= amount | `(account, token, threshold, isGreaterThan)` |
| **CUSTOM_ORACLE** | `4` | Custom oracle check | `(oracleAddress, callData)` |
| **MULTI_CONDITION** | `5` | Combine conditions with AND/OR | `(useAnd, conditions[])` |

---

## 🎯 Reputation Tiers

| Tier | Tasks | Success Rate | Fee Multiplier | Benefits |
|------|-------|--------------|----------------|----------|
| **Rookie** | 0-10 | Any | 100% | Basic tasks only |
| **Bronze** | 11-100 | >80% | 105% (+5%) | Priority on standard tasks |
| **Silver** | 101-500 | >90% | 110% (+10%) | Access to premium tasks |
| **Gold** | 501-2000 | >95% | 115% (+15%) | Exclusive high-value tasks |
| **Diamond** | 2001+ | >98% | 120% (+20%) | VIP access + verified badge |

---

## 🔐 Security Considerations

### Protocol Whitelist

Only approved protocols can be called:

```solidity
// Owner approves protocols
await taskRegistry.approveProtocol(UNISWAP_ROUTER);
await taskRegistry.approveProtocol(AAVE_POOL);
```

### Execution Locks

Tasks are locked for 30 seconds during execution to prevent front-running:

```solidity
// Task locked when executor starts execution
// Other executors must wait until lock expires or execution completes
```

### Gas Limits

Actions have gas limits to prevent DoS:

```solidity
uint256 public maxGasPerAction = 500000;
```

### Escrow Safety

Rewards are locked in escrow and only released upon successful execution:

```solidity
// Funds locked on task creation
// Released to executor only if execution succeeds
// Refunded to creator if task cancelled
```

---

## 🧪 Testing

Run the full test suite:

```bash
npx hardhat test
```

Run specific test:

```bash
npx hardhat test --grep "Should create a simple task"
```

Run with gas reporting:

```bash
REPORT_GAS=true npx hardhat test
```

---

## 📊 Gas Estimates

| Operation | Gas Cost | Native Cost @ 100 Gwei |
|-----------|----------|------------------------|
| Create Task | ~150,000 | ~0.015 ETH |
| Execute Task (simple) | ~100,000 | ~0.010 ETH |
| Execute Task (complex) | ~300,000 | ~0.030 ETH |
| Register Executor | ~50,000 | ~0.005 ETH |
| Cancel Task | ~60,000 | ~0.006 ETH |

---

## 🌐 Supported Networks

### PassetHub Testnet (Current)
- Network ID: `polkadotHubTestnet`
- RPC: `https://testnet-passet-hub-eth-rpc.polkadot.io`
- Chain ID: Check Hardhat config
- Native Token: Test tokens (faucet available)

### Future Networks
- Moonbeam (Polkadot parachain)
- Moonriver (Kusama parachain)
- Astar (Polkadot parachain)

---

## 🛠️ Adding New Protocol Adapters

### 1. Create Adapter Contract

```solidity
// contracts/adapters/AaveAdapter.sol
contract AaveAdapter {
    function execute(
        uint256 _taskId,
        address _protocol,
        bytes4 _selector,
        bytes calldata _params,
        uint256 _value
    ) external returns (bool) {
        // Implement Aave interaction logic
    }
}
```

### 2. Deploy Adapter

```typescript
const AaveAdapter = await ethers.getContractFactory("AaveAdapter");
const aaveAdapter = await AaveAdapter.deploy();
```

### 3. Register Adapter

```typescript
await actionRouter.registerAdapter(AAVE_POOL, aaveAdapter.address);
await actionRouter.approveProtocol(AAVE_POOL);
await taskRegistry.approveProtocol(AAVE_POOL);
```

---

## 📚 Additional Resources

- [Polkadot Documentation](https://docs.polkadot.network/)
- [Hardhat Polkadot Plugin](https://github.com/paritytech/hardhat-polkadot)
- [Moonbeam Docs](https://docs.moonbeam.network/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

---

## 📄 License

MIT License - see LICENSE file for details

---

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always audit smart contracts before using on mainnet.

---

## 📧 Support

For issues and questions:
- GitHub Issues: [Create an issue](https://github.com/your-repo/issues)
- Discord: [Join our community](#)
- Twitter: [@YourProject](#)

---

**Built with ❤️ on Polkadot**
