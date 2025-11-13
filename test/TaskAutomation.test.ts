import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  DynamicTaskRegistry,
  PaymentEscrow,
  ExecutorManager,
  ReputationSystem,
  ActionRouter,
  ConditionChecker,
} from "../typechain-types";

describe("Task Automation System", function () {
  let taskRegistry: DynamicTaskRegistry;
  let paymentEscrow: PaymentEscrow;
  let executorManager: ExecutorManager;
  let reputationSystem: ReputationSystem;
  let actionRouter: ActionRouter;
  let conditionChecker: ConditionChecker;

  let owner: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let user: SignerWithAddress;
  let executor: SignerWithAddress;

  const PLATFORM_FEE = 100; // 1%
  const REWARD = ethers.parseEther("1");

  beforeEach(async function () {
    [owner, feeRecipient, user, executor] = await ethers.getSigners();

    // Deploy contracts
    const PaymentEscrow = await ethers.getContractFactory("PaymentEscrow");
    paymentEscrow = await PaymentEscrow.deploy(feeRecipient.address);

    const ConditionChecker = await ethers.getContractFactory("ConditionChecker");
    conditionChecker = await ConditionChecker.deploy();

    const ActionRouter = await ethers.getContractFactory("ActionRouter");
    actionRouter = await ActionRouter.deploy();

    const ExecutorManager = await ethers.getContractFactory("ExecutorManager");
    executorManager = await ExecutorManager.deploy();

    const ReputationSystem = await ethers.getContractFactory("ReputationSystem");
    reputationSystem = await ReputationSystem.deploy();

    const TaskRegistry = await ethers.getContractFactory("DynamicTaskRegistry");
    taskRegistry = await TaskRegistry.deploy();

    // Configure contracts
    await paymentEscrow.setTaskRegistry(await taskRegistry.getAddress());
    await actionRouter.setTaskRegistry(await taskRegistry.getAddress());
    await executorManager.setTaskRegistry(await taskRegistry.getAddress());
    await reputationSystem.authorizeUpdater(await taskRegistry.getAddress());

    await taskRegistry.setConditionChecker(await conditionChecker.getAddress());
    await taskRegistry.setActionRouter(await actionRouter.getAddress());
    await taskRegistry.setExecutorManager(await executorManager.getAddress());
    await taskRegistry.setPaymentEscrow(await paymentEscrow.getAddress());
    await taskRegistry.setReputationSystem(await reputationSystem.getAddress());
    await taskRegistry.setPlatformFee(PLATFORM_FEE);
  });

  describe("Deployment", function () {
    it("Should deploy all contracts successfully", async function () {
      expect(await taskRegistry.getAddress()).to.be.properAddress;
      expect(await paymentEscrow.getAddress()).to.be.properAddress;
      expect(await executorManager.getAddress()).to.be.properAddress;
      expect(await reputationSystem.getAddress()).to.be.properAddress;
      expect(await actionRouter.getAddress()).to.be.properAddress;
      expect(await conditionChecker.getAddress()).to.be.properAddress;
    });

    it("Should configure contracts correctly", async function () {
      expect(await taskRegistry.conditionChecker()).to.equal(await conditionChecker.getAddress());
      expect(await taskRegistry.actionRouter()).to.equal(await actionRouter.getAddress());
      expect(await taskRegistry.executorManager()).to.equal(await executorManager.getAddress());
      expect(await taskRegistry.paymentEscrow()).to.equal(await paymentEscrow.getAddress());
      expect(await taskRegistry.platformFeePercentage()).to.equal(PLATFORM_FEE);
    });
  });

  describe("Task Creation", function () {
    it("Should create a simple task", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = {
        conditionType: 0, // ALWAYS
        conditionData: "0x",
      };

      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      const tx = await taskRegistry.connect(user).createTask(
        condition,
        [action],
        REWARD,
        0, // No expiry
        1, // One-time
        0, // No interval
        { value: REWARD }
      );

      await expect(tx)
        .to.emit(taskRegistry, "TaskCreated")
        .withArgs(0, user.address, REWARD, 1);

      const task = await taskRegistry.tasks(0);
      expect(task.creator).to.equal(user.address);
      expect(task.reward).to.equal(REWARD);
      expect(task.status).to.equal(0); // ACTIVE
    });

    it("Should fail if protocol not approved", async function () {
      const unapprovedProtocol = ethers.Wallet.createRandom().address;

      const condition = {
        conditionType: 0,
        conditionData: "0x",
      };

      const action = {
        protocol: unapprovedProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await expect(
        taskRegistry.connect(user).createTask(
          condition,
          [action],
          REWARD,
          0,
          1,
          0,
          { value: REWARD }
        )
      ).to.be.revertedWith("Protocol not approved");
    });

    it("Should fail if insufficient funding", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = {
        conditionType: 0,
        conditionData: "0x",
      };

      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await expect(
        taskRegistry.connect(user).createTask(
          condition,
          [action],
          REWARD,
          0,
          1,
          0,
          { value: REWARD / 2n } // Insufficient
        )
      ).to.be.revertedWith("Insufficient funding");
    });
  });

  describe("Executor Registration", function () {
    it("Should register executor", async function () {
      await expect(executorManager.connect(executor).registerExecutor())
        .to.emit(executorManager, "ExecutorRegistered")
        .withArgs(executor.address, await ethers.provider.getBlock("latest").then(b => b?.timestamp));

      const executorData = await executorManager.getExecutor(executor.address);
      expect(executorData.isRegistered).to.be.true;
      expect(executorData.totalExecutions).to.equal(0);
    });

    it("Should fail to register twice", async function () {
      await executorManager.connect(executor).registerExecutor();

      await expect(
        executorManager.connect(executor).registerExecutor()
      ).to.be.revertedWith("Already registered");
    });

    it("Should check executor can execute", async function () {
      await executorManager.connect(executor).registerExecutor();

      const canExecute = await executorManager.canExecute(executor.address);
      expect(canExecute).to.be.true;
    });
  });

  describe("Task Cancellation", function () {
    it("Should cancel task and refund creator", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = { conditionType: 0, conditionData: "0x" };
      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await taskRegistry.connect(user).createTask(
        condition,
        [action],
        REWARD,
        0,
        1,
        0,
        { value: REWARD }
      );

      const balanceBefore = await ethers.provider.getBalance(user.address);

      const tx = await taskRegistry.connect(user).cancelTask(0);
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const balanceAfter = await ethers.provider.getBalance(user.address);

      // User should get refund minus gas
      expect(balanceAfter).to.be.closeTo(
        balanceBefore + REWARD - gasUsed,
        ethers.parseEther("0.01") // Allow small variance
      );

      const task = await taskRegistry.tasks(0);
      expect(task.status).to.equal(4); // CANCELLED
    });

    it("Should fail to cancel if not creator", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = { conditionType: 0, conditionData: "0x" };
      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await taskRegistry.connect(user).createTask(
        condition,
        [action],
        REWARD,
        0,
        1,
        0,
        { value: REWARD }
      );

      await expect(
        taskRegistry.connect(executor).cancelTask(0)
      ).to.be.revertedWith("Not task creator");
    });
  });

  describe("Condition Checking", function () {
    it("Should check ALWAYS condition", async function () {
      const result = await conditionChecker.checkCondition(0, "0x");
      expect(result).to.be.true;
    });

    it("Should check TIME_BASED condition", async function () {
      const futureTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;
      const conditionData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256"],
        [futureTime]
      );

      const result = await conditionChecker.checkCondition(2, conditionData);
      expect(result).to.be.false; // Should be false (time not reached)
    });

    it("Should check BALANCE_THRESHOLD condition", async function () {
      const conditionData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "uint256", "bool"],
        [user.address, ethers.ZeroAddress, ethers.parseEther("1"), true]
      );

      const result = await conditionChecker.checkCondition(3, conditionData);
      expect(result).to.be.true; // User should have balance
    });
  });

  describe("Reputation System", function () {
    it("Should record success and update reputation", async function () {
      await reputationSystem.recordSuccess(executor.address, 0, REWARD);

      const rep = await reputationSystem.getReputation(executor.address);
      expect(rep.totalTasks).to.equal(1);
      expect(rep.successfulTasks).to.equal(1);
      expect(rep.totalRewardsEarned).to.equal(REWARD);
    });

    it("Should calculate success rate correctly", async function () {
      await reputationSystem.recordSuccess(executor.address, 0, REWARD);
      await reputationSystem.recordSuccess(executor.address, 1, REWARD);
      await reputationSystem.recordFailure(executor.address, 2);

      const successRate = await reputationSystem.getSuccessRate(executor.address);
      expect(successRate).to.equal(6666); // 66.66% (2 out of 3)
    });

    it("Should promote to higher tiers", async function () {
      // Execute many successful tasks to reach BRONZE tier (11 tasks, >80% success)
      for (let i = 0; i < 11; i++) {
        await reputationSystem.recordSuccess(executor.address, i, REWARD);
      }

      const rep = await reputationSystem.getReputation(executor.address);
      expect(rep.tier).to.equal(1); // BRONZE
    });
  });

  describe("Payment Escrow", function () {
    it("Should lock funds for task", async function () {
      const taskId = 0;

      const tx = await paymentEscrow.lockFunds(taskId, user.address, REWARD, {
        value: REWARD,
      });

      await expect(tx)
        .to.emit(paymentEscrow, "FundsLocked")
        .withArgs(taskId, user.address, REWARD);

      const escrow = await paymentEscrow.getEscrow(taskId);
      expect(escrow.totalLocked).to.equal(REWARD);
      expect(escrow.isActive).to.be.true;
    });

    it("Should release payment to executor", async function () {
      const taskId = 0;

      await paymentEscrow.lockFunds(taskId, user.address, REWARD, {
        value: REWARD,
      });

      const balanceBefore = await ethers.provider.getBalance(executor.address);

      await paymentEscrow.releasePayment(
        taskId,
        executor.address,
        REWARD,
        PLATFORM_FEE
      );

      const balanceAfter = await ethers.provider.getBalance(executor.address);

      const expectedPayout = REWARD - (REWARD * BigInt(PLATFORM_FEE)) / 10000n;
      expect(balanceAfter - balanceBefore).to.equal(expectedPayout);
    });
  });

  describe("Action Router", function () {
    it("Should approve protocols", async function () {
      const protocol = ethers.Wallet.createRandom().address;

      await expect(actionRouter.approveProtocol(protocol))
        .to.emit(actionRouter, "ProtocolApproved")
        .withArgs(protocol);

      expect(await actionRouter.approvedProtocols(protocol)).to.be.true;
    });

    it("Should register adapters", async function () {
      const protocol = ethers.Wallet.createRandom().address;
      const adapter = ethers.Wallet.createRandom().address;

      await expect(actionRouter.registerAdapter(protocol, adapter))
        .to.emit(actionRouter, "AdapterRegistered")
        .withArgs(protocol, adapter);

      expect(await actionRouter.protocolAdapters(protocol)).to.equal(adapter);
    });
  });

  describe("Task Lifecycle", function () {
    it("Should pause and resume task", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = { conditionType: 0, conditionData: "0x" };
      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await taskRegistry.connect(user).createTask(
        condition,
        [action],
        REWARD,
        0,
        1,
        0,
        { value: REWARD }
      );

      await taskRegistry.connect(user).pauseTask(0);
      let task = await taskRegistry.tasks(0);
      expect(task.status).to.equal(1); // PAUSED

      await taskRegistry.connect(user).resumeTask(0);
      task = await taskRegistry.tasks(0);
      expect(task.status).to.equal(0); // ACTIVE
    });

    it("Should get executable tasks", async function () {
      const mockProtocol = ethers.Wallet.createRandom().address;
      await taskRegistry.approveProtocol(mockProtocol);

      const condition = { conditionType: 0, conditionData: "0x" };
      const action = {
        protocol: mockProtocol,
        selector: "0x12345678",
        params: "0x",
        value: 0,
      };

      await taskRegistry.connect(user).createTask(
        condition,
        [action],
        REWARD,
        0,
        1,
        0,
        { value: REWARD }
      );

      const executableTasks = await taskRegistry.getExecutableTasks(10);
      expect(executableTasks.length).to.equal(1);
      expect(executableTasks[0].id).to.equal(0);
    });
  });
});
