import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Hardhat Ignition module for deploying the complete Task Automation System
 *
 * Deployment Order:
 * 1. PaymentEscrow
 * 2. ConditionChecker
 * 3. ActionRouter
 * 4. ExecutorManager
 * 5. ReputationSystem
 * 6. DynamicTaskRegistry
 * 7. UniswapLimitOrderAdapter
 * 8. Configure all contracts
 */
const TaskAutomationModule = buildModule("TaskAutomationSystem", (m) => {

  // ============ Parameters ============

  // Default fee recipient (can be changed later)
  const feeRecipient = m.getParameter("feeRecipient", m.getAccount(0));

  // Platform fee (100 = 1%)
  const platformFee = m.getParameter("platformFee", 100);

  // ============ 1. Deploy PaymentEscrow ============

  const paymentEscrow = m.contract("PaymentEscrow", [feeRecipient]);

  // ============ 2. Deploy ConditionChecker ============

  const conditionChecker = m.contract("ConditionChecker");

  // ============ 3. Deploy ActionRouter ============

  const actionRouter = m.contract("ActionRouter");

  // ============ 4. Deploy ExecutorManager ============

  const executorManager = m.contract("ExecutorManager");

  // ============ 5. Deploy ReputationSystem ============

  const reputationSystem = m.contract("ReputationSystem");

  // ============ 6. Deploy DynamicTaskRegistry ============

  const taskRegistry = m.contract("DynamicTaskRegistry");

  // ============ 7. Deploy UniswapLimitOrderAdapter ============

  const uniswapAdapter = m.contract("UniswapLimitOrderAdapter");

  // ============ 8. Configure Contracts ============

  // Configure PaymentEscrow
  m.call(paymentEscrow, "setTaskRegistry", [taskRegistry]);

  // Configure ActionRouter
  m.call(actionRouter, "setTaskRegistry", [taskRegistry]);

  // Configure ExecutorManager
  m.call(executorManager, "setTaskRegistry", [taskRegistry]);

  // Configure ReputationSystem
  m.call(reputationSystem, "authorizeUpdater", [taskRegistry]);

  // Configure UniswapAdapter
  m.call(uniswapAdapter, "setActionRouter", [actionRouter]);

  // Configure DynamicTaskRegistry with all dependencies
  m.call(taskRegistry, "setConditionChecker", [conditionChecker]);
  m.call(taskRegistry, "setActionRouter", [actionRouter]);
  m.call(taskRegistry, "setExecutorManager", [executorManager]);
  m.call(taskRegistry, "setPaymentEscrow", [paymentEscrow]);
  m.call(taskRegistry, "setReputationSystem", [reputationSystem]);
  m.call(taskRegistry, "setPlatformFee", [platformFee]);

  // ============ Return Deployed Contracts ============

  return {
    paymentEscrow,
    conditionChecker,
    actionRouter,
    executorManager,
    reputationSystem,
    taskRegistry,
    uniswapAdapter,
  };
});

export default TaskAutomationModule;
