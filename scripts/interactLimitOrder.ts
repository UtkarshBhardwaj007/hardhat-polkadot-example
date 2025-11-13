import { ethers } from "hardhat";

/**
 * Interaction script for creating and executing limit order tasks
 *
 * This demonstrates the complete workflow:
 * 1. Deploy system (or connect to existing)
 * 2. Setup protocols and adapters
 * 3. Create a limit order task
 * 4. Register as executor
 * 5. Execute the task
 */

async function main() {
  const [deployer, user, executor] = await ethers.getSigners();

  console.log("\n🚀 Task Automation System - Limit Order Demo");
  console.log("=".repeat(60));

  // ============ 1. Connect to Deployed Contracts ============

  console.log("\n📡 Connecting to deployed contracts...");

  // You'll need to update these addresses after deployment
  // Or load them from ignition/deployments/<chain-id>/deployed_addresses.json
  const TASK_REGISTRY_ADDRESS = process.env.TASK_REGISTRY_ADDRESS || "";
  const EXECUTOR_MANAGER_ADDRESS = process.env.EXECUTOR_MANAGER_ADDRESS || "";
  const ACTION_ROUTER_ADDRESS = process.env.ACTION_ROUTER_ADDRESS || "";
  const UNISWAP_ADAPTER_ADDRESS = process.env.UNISWAP_ADAPTER_ADDRESS || "";

  if (!TASK_REGISTRY_ADDRESS) {
    console.log("⚠️  Contract addresses not set. Please deploy first using:");
    console.log("   npx hardhat ignition deploy ignition/modules/TaskAutomationSystem.ts --network polkadotHubTestnet");
    return;
  }

  const taskRegistry = await ethers.getContractAt("DynamicTaskRegistry", TASK_REGISTRY_ADDRESS);
  const executorManager = await ethers.getContractAt("ExecutorManager", EXECUTOR_MANAGER_ADDRESS);
  const actionRouter = await ethers.getContractAt("ActionRouter", ACTION_ROUTER_ADDRESS);
  const uniswapAdapter = await ethers.getContractAt("UniswapLimitOrderAdapter", UNISWAP_ADAPTER_ADDRESS);

  console.log("✅ Connected to contracts");

  // ============ 2. Setup Protocols ============

  console.log("\n⚙️  Setting up protocols and adapters...");

  // Example DEX router on Moonbeam (StellaSwap or similar)
  const UNISWAP_ROUTER = process.env.UNISWAP_ROUTER || "0x70085a09D30D6f8C4ecF6eE10120d1847383BB57"; // Example

  // Approve router in ActionRouter
  const approveRouterTx = await actionRouter.approveProtocol(UNISWAP_ROUTER);
  await approveRouterTx.wait();
  console.log(`✅ Approved router: ${UNISWAP_ROUTER}`);

  // Register adapter in ActionRouter
  const registerAdapterTx = await actionRouter.registerAdapter(UNISWAP_ROUTER, UNISWAP_ADAPTER_ADDRESS);
  await registerAdapterTx.wait();
  console.log(`✅ Registered adapter for router`);

  // Approve router in TaskRegistry
  const approveInRegistryTx = await taskRegistry.approveProtocol(UNISWAP_ROUTER);
  await approveInRegistryTx.wait();
  console.log(`✅ Approved protocol in TaskRegistry`);

  // Add router to adapter
  const addRouterTx = await uniswapAdapter.addRouter(UNISWAP_ROUTER);
  await addRouterTx.wait();
  console.log(`✅ Added router to adapter`);

  // ============ 3. Create Limit Order Task ============

  console.log("\n📝 Creating limit order task...");

  // Example: Swap 100 USDC for ETH when price is favorable
  const TOKEN_IN = process.env.TOKEN_IN || "0x931715FEE2d06333043d11F658C8CE934aC61D0c"; // USDC on Moonbeam
  const TOKEN_OUT = process.env.TOKEN_OUT || "0xAcc15dC74880C9944775448304B263D191c6077F"; // WGLMR on Moonbeam
  const AMOUNT_IN = ethers.parseUnits("100", 6); // 100 USDC (6 decimals)
  const MIN_AMOUNT_OUT = ethers.parseEther("10"); // Min 10 WGLMR

  const REWARD = ethers.parseEther("0.25"); // 0.25 GLMR reward for executor

  // Encode action parameters
  const actionParams = ethers.AbiCoder.defaultAbiCoder().encode(
    ["address", "address", "uint256", "uint256", "address", "address"],
    [
      TOKEN_IN,        // tokenIn
      TOKEN_OUT,       // tokenOut
      AMOUNT_IN,       // amountIn
      MIN_AMOUNT_OUT,  // amountOutMin
      user.address,    // recipient
      user.address,    // creator (token owner)
    ]
  );

  // Create condition (ALWAYS for now - will execute immediately when price is good)
  const condition = {
    conditionType: 0, // ALWAYS
    conditionData: "0x",
  };

  // Create action
  const action = {
    protocol: UNISWAP_ROUTER,
    selector: "0x38ed1739", // swapExactTokensForTokens selector
    params: actionParams,
    value: 0,
  };

  // Approve tokens for adapter (user must have USDC)
  console.log("\n💰 Approving tokens...");
  const tokenIn = await ethers.getContractAt("IERC20", TOKEN_IN);
  const approveTx = await tokenIn.connect(user).approve(UNISWAP_ADAPTER_ADDRESS, AMOUNT_IN);
  await approveTx.wait();
  console.log("✅ Tokens approved");

  // Create task
  console.log("\n🎯 Creating task...");
  const createTaskTx = await taskRegistry.connect(user).createTask(
    condition,
    [action],
    REWARD,
    0, // No expiry
    1, // One-time execution
    0, // No recurring interval
    { value: REWARD }
  );

  const receipt = await createTaskTx.wait();
  const taskId = receipt?.logs[0]?.topics[1] ? BigInt(receipt.logs[0].topics[1]) : 0n;

  console.log(`✅ Task created! Task ID: ${taskId}`);

  // ============ 4. Register as Executor ============

  console.log("\n👷 Registering as executor...");

  const registerTx = await executorManager.connect(executor).registerExecutor();
  await registerTx.wait();

  console.log(`✅ Executor registered: ${executor.address}`);

  // ============ 5. Execute Task ============

  console.log("\n⚡ Executing task...");

  try {
    const executeTx = await executorManager.connect(executor).attemptExecute(taskId);
    const execReceipt = await executeTx.wait();

    console.log("✅ Task executed successfully!");
    console.log(`   Gas used: ${execReceipt?.gasUsed.toString()}`);
    console.log(`   Executor earned: ${ethers.formatEther(REWARD)} GLMR`);

    // ============ 6. Check Results ============

    console.log("\n📊 Checking task status...");

    const task = await taskRegistry.tasks(taskId);
    console.log(`   Status: ${task.status} (2 = COMPLETED)`);
    console.log(`   Execution count: ${task.executionCount}`);

    const executorStats = await executorManager.getExecutor(executor.address);
    console.log(`\n👤 Executor stats:`);
    console.log(`   Total executions: ${executorStats.totalExecutions}`);
    console.log(`   Successful: ${executorStats.successfulExecutions}`);
    console.log(`   Failed: ${executorStats.failedExecutions}`);

  } catch (error: any) {
    console.error("❌ Task execution failed:");
    console.error(error.message);
  }

  console.log("\n" + "=".repeat(60));
  console.log("✅ Demo completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
