// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DynamicTaskRegistry
 * @notice Registry for dynamic, composable automation tasks
 * @dev Enables users to create tasks that execute arbitrary protocol interactions
 *      when specific conditions are met. Executors earn rewards for completing tasks.
 */
contract DynamicTaskRegistry is Ownable, ReentrancyGuard {

    // ============ Type Definitions ============

    /**
     * @notice Task structure containing all task metadata and execution logic
     * @param id Unique task identifier
     * @param creator Address that created the task
     * @param reward Amount paid to executor per successful execution
     * @param createdAt Block timestamp when task was created
     * @param expiresAt Expiration timestamp (0 = no expiry)
     * @param status Current task status
     * @param condition Execution condition that must be met
     * @param actions Array of protocol interactions to execute
     * @param executionCount Number of times task has been executed
     * @param maxExecutions Maximum allowed executions (0 = unlimited recurring)
     * @param lastExecutionTime Timestamp of last successful execution
     * @param recurringInterval Minimum time between executions (for recurring tasks)
     */
    struct Task {
        uint256 id;
        address creator;
        uint256 reward;
        uint256 createdAt;
        uint256 expiresAt;
        TaskStatus status;

        // Dynamic components
        Condition condition;
        Action[] actions;

        // Execution tracking
        uint256 executionCount;
        uint256 maxExecutions;
        uint256 lastExecutionTime;
        uint256 recurringInterval;
    }

    /**
     * @notice Condition that must be satisfied for task execution
     * @param conditionType Type of condition to check
     * @param conditionData ABI-encoded parameters for the condition
     */
    struct Condition {
        ConditionType conditionType;
        bytes conditionData;
    }

    /**
     * @notice Available condition types for task execution
     */
    enum ConditionType {
        ALWAYS,              // Execute immediately (no condition)
        PRICE_THRESHOLD,     // Asset price >= or <= threshold
        TIME_BASED,          // Execute after specific timestamp
        BALANCE_THRESHOLD,   // Account balance >= threshold
        CUSTOM_ORACLE,       // Custom oracle check
        MULTI_CONDITION      // Combine multiple conditions with AND/OR
    }

    /**
     * @notice Action to execute when condition is met
     * @param protocol Address of protocol to interact with
     * @param selector Function selector to call
     * @param params ABI-encoded function parameters
     * @param value ETH value to send with call (if needed)
     */
    struct Action {
        address protocol;
        bytes4 selector;
        bytes params;
        uint256 value;
    }

    /**
     * @notice Task lifecycle states
     */
    enum TaskStatus {
        ACTIVE,      // Ready for execution
        PAUSED,      // Temporarily disabled by creator
        EXECUTING,   // Currently being executed
        COMPLETED,   // All executions finished
        CANCELLED,   // Cancelled by creator
        EXPIRED      // Past expiration time
    }

    // ============ State Variables ============

    /// @notice Counter for generating unique task IDs
    uint256 public nextTaskId;

    /// @notice Mapping from task ID to Task data
    mapping(uint256 => Task) public tasks;

    /// @notice Tasks created by each address
    mapping(address => uint256[]) public creatorTasks;

    /// @notice Tasks executed by each executor
    mapping(address => uint256[]) public executorHistory;

    /// @notice Addresses of dependent contracts
    address public conditionChecker;
    address public actionRouter;
    address public executorManager;
    address public paymentEscrow;
    address public reputationSystem;

    /// @notice Platform fee in basis points (100 = 1%)
    uint256 public platformFeePercentage = 100;
    uint256 public constant MAX_PLATFORM_FEE = 500; // 5% maximum

    /// @notice Whitelist of approved protocols for security
    mapping(address => bool) public approvedProtocols;

    /// @notice Whitelist of approved adapters
    mapping(address => bool) public approvedAdapters;

    /// @notice Maximum number of actions per task
    uint256 public constant MAX_ACTIONS = 10;

    // ============ Events ============

    event TaskCreated(
        uint256 indexed taskId,
        address indexed creator,
        uint256 reward,
        uint256 maxExecutions
    );

    event TaskExecuted(
        uint256 indexed taskId,
        address indexed executor,
        bool success,
        uint256 gasUsed
    );

    event TaskCancelled(
        uint256 indexed taskId,
        address indexed creator,
        uint256 refundAmount
    );

    event TaskUpdated(
        uint256 indexed taskId,
        uint256 newReward
    );

    event TaskStatusChanged(
        uint256 indexed taskId,
        TaskStatus oldStatus,
        TaskStatus newStatus
    );

    event ProtocolApproved(address indexed protocol);
    event ProtocolRevoked(address indexed protocol);

    // ============ Modifiers ============

    modifier onlyTaskCreator(uint256 _taskId) {
        require(tasks[_taskId].creator == msg.sender, "Not task creator");
        _;
    }

    modifier onlyExecutorManager() {
        require(msg.sender == executorManager, "Not executor manager");
        _;
    }

    modifier taskExists(uint256 _taskId) {
        require(tasks[_taskId].creator != address(0), "Task does not exist");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Core Functions ============

    /**
     * @notice Create a new dynamic task
     * @param _condition Execution condition
     * @param _actions Array of actions to execute
     * @param _reward Executor reward per execution
     * @param _expiresAt Expiration timestamp (0 = no expiry)
     * @param _maxExecutions Maximum executions (0 = one-time, >0 = recurring)
     * @param _recurringInterval Minimum time between recurring executions
     * @return taskId The created task ID
     */
    function createTask(
        Condition calldata _condition,
        Action[] calldata _actions,
        uint256 _reward,
        uint256 _expiresAt,
        uint256 _maxExecutions,
        uint256 _recurringInterval
    ) external payable nonReentrant returns (uint256 taskId) {
        require(_actions.length > 0, "No actions specified");
        require(_actions.length <= MAX_ACTIONS, "Too many actions");
        require(_reward > 0, "Invalid reward amount");
        require(
            _expiresAt == 0 || _expiresAt > block.timestamp,
            "Invalid expiration time"
        );

        // Validate all protocols are approved
        for (uint256 i = 0; i < _actions.length; i++) {
            require(
                approvedProtocols[_actions[i].protocol],
                "Protocol not approved"
            );
        }

        // Calculate total funding required
        uint256 totalFunding = _maxExecutions == 0
            ? _reward
            : _reward * _maxExecutions;

        require(msg.value >= totalFunding, "Insufficient funding");

        // Create task
        taskId = nextTaskId++;
        Task storage task = tasks[taskId];

        task.id = taskId;
        task.creator = msg.sender;
        task.reward = _reward;
        task.createdAt = block.timestamp;
        task.expiresAt = _expiresAt;
        task.status = TaskStatus.ACTIVE;
        task.condition = _condition;
        task.executionCount = 0;
        task.maxExecutions = _maxExecutions;
        task.lastExecutionTime = 0;
        task.recurringInterval = _recurringInterval;

        // Store actions
        for (uint256 i = 0; i < _actions.length; i++) {
            task.actions.push(_actions[i]);
        }

        // Add to creator's task list
        creatorTasks[msg.sender].push(taskId);

        // Lock funds in escrow
        (bool success, ) = paymentEscrow.call{value: totalFunding}(
            abi.encodeWithSignature(
                "lockFunds(uint256,address,uint256)",
                taskId,
                msg.sender,
                totalFunding
            )
        );
        require(success, "Escrow lock failed");

        emit TaskCreated(taskId, msg.sender, _reward, _maxExecutions);
    }

    /**
     * @notice Execute a task (called by ExecutorManager)
     * @param _taskId Task to execute
     * @param _executor Address of executor
     * @return success Whether execution succeeded
     */
    function executeTask(
        uint256 _taskId,
        address _executor
    ) external onlyExecutorManager taskExists(_taskId) nonReentrant returns (bool success) {
        Task storage task = tasks[_taskId];

        // Validate task is executable
        require(task.status == TaskStatus.ACTIVE, "Task not active");
        require(
            task.expiresAt == 0 || block.timestamp <= task.expiresAt,
            "Task expired"
        );
        require(
            task.maxExecutions == 0 || task.executionCount < task.maxExecutions,
            "Max executions reached"
        );

        // Check recurring interval
        if (task.recurringInterval > 0 && task.lastExecutionTime > 0) {
            require(
                block.timestamp >= task.lastExecutionTime + task.recurringInterval,
                "Recurring interval not met"
            );
        }

        // Lock task during execution
        TaskStatus oldStatus = task.status;
        task.status = TaskStatus.EXECUTING;
        emit TaskStatusChanged(_taskId, oldStatus, TaskStatus.EXECUTING);

        uint256 gasBefore = gasleft();

        // Check condition
        bool conditionMet = _checkCondition(task.condition);

        if (!conditionMet) {
            task.status = TaskStatus.ACTIVE;
            emit TaskStatusChanged(_taskId, TaskStatus.EXECUTING, TaskStatus.ACTIVE);
            emit TaskExecuted(_taskId, _executor, false, gasBefore - gasleft());
            return false;
        }

        // Execute actions
        bool execSuccess = _executeActions(_taskId, task.actions);

        uint256 gasUsed = gasBefore - gasleft();

        if (execSuccess) {
            // Update execution tracking
            task.executionCount++;
            task.lastExecutionTime = block.timestamp;

            // Release payment to executor
            (bool paySuccess, ) = paymentEscrow.call(
                abi.encodeWithSignature(
                    "releasePayment(uint256,address,uint256,uint256)",
                    _taskId,
                    _executor,
                    task.reward,
                    platformFeePercentage
                )
            );
            require(paySuccess, "Payment release failed");

            // Update reputation
            if (reputationSystem != address(0)) {
                (bool repSuccess, ) = reputationSystem.call(
                    abi.encodeWithSignature(
                        "recordSuccess(address,uint256)",
                        _executor,
                        _taskId
                    )
                );
                // Don't revert on reputation failure
            }

            // Update task status
            if (task.maxExecutions > 0 && task.executionCount >= task.maxExecutions) {
                task.status = TaskStatus.COMPLETED;
                emit TaskStatusChanged(_taskId, TaskStatus.EXECUTING, TaskStatus.COMPLETED);
            } else {
                task.status = TaskStatus.ACTIVE;
                emit TaskStatusChanged(_taskId, TaskStatus.EXECUTING, TaskStatus.ACTIVE);
            }

            // Add to executor history
            executorHistory[_executor].push(_taskId);

            emit TaskExecuted(_taskId, _executor, true, gasUsed);
            return true;
        } else {
            // Execution failed - unlock task
            task.status = TaskStatus.ACTIVE;
            emit TaskStatusChanged(_taskId, TaskStatus.EXECUTING, TaskStatus.ACTIVE);
            emit TaskExecuted(_taskId, _executor, false, gasUsed);
            return false;
        }
    }

    /**
     * @notice Cancel a task and refund remaining funds
     * @param _taskId Task to cancel
     */
    function cancelTask(
        uint256 _taskId
    ) external onlyTaskCreator(_taskId) taskExists(_taskId) nonReentrant {
        Task storage task = tasks[_taskId];

        require(
            task.status == TaskStatus.ACTIVE || task.status == TaskStatus.PAUSED,
            "Cannot cancel task in current state"
        );

        TaskStatus oldStatus = task.status;
        task.status = TaskStatus.CANCELLED;
        emit TaskStatusChanged(_taskId, oldStatus, TaskStatus.CANCELLED);

        // Calculate refund amount
        uint256 remainingExecutions = task.maxExecutions == 0
            ? 1
            : task.maxExecutions - task.executionCount;
        uint256 refundAmount = task.reward * remainingExecutions;

        // Process refund from escrow
        (bool success, ) = paymentEscrow.call(
            abi.encodeWithSignature(
                "refund(uint256,address,uint256)",
                _taskId,
                task.creator,
                refundAmount
            )
        );
        require(success, "Refund failed");

        emit TaskCancelled(_taskId, task.creator, refundAmount);
    }

    /**
     * @notice Update task reward (with additional funding if needed)
     * @param _taskId Task to update
     * @param _newReward New reward amount
     */
    function updateTaskReward(
        uint256 _taskId,
        uint256 _newReward
    ) external payable onlyTaskCreator(_taskId) taskExists(_taskId) nonReentrant {
        Task storage task = tasks[_taskId];

        require(task.status == TaskStatus.ACTIVE, "Task not active");
        require(_newReward > 0, "Invalid reward");

        uint256 oldReward = task.reward;

        if (_newReward > oldReward) {
            // Increasing reward - need additional funds
            uint256 remainingExecutions = task.maxExecutions == 0
                ? 1
                : task.maxExecutions - task.executionCount;
            uint256 additionalFunding = (_newReward - oldReward) * remainingExecutions;

            require(msg.value >= additionalFunding, "Insufficient additional funding");

            // Add funds to escrow
            (bool success, ) = paymentEscrow.call{value: additionalFunding}(
                abi.encodeWithSignature(
                    "addFunds(uint256,uint256)",
                    _taskId,
                    additionalFunding
                )
            );
            require(success, "Escrow funding failed");
        }

        task.reward = _newReward;
        emit TaskUpdated(_taskId, _newReward);
    }

    /**
     * @notice Pause an active task
     * @param _taskId Task to pause
     */
    function pauseTask(
        uint256 _taskId
    ) external onlyTaskCreator(_taskId) taskExists(_taskId) {
        Task storage task = tasks[_taskId];
        require(task.status == TaskStatus.ACTIVE, "Task not active");

        task.status = TaskStatus.PAUSED;
        emit TaskStatusChanged(_taskId, TaskStatus.ACTIVE, TaskStatus.PAUSED);
    }

    /**
     * @notice Resume a paused task
     * @param _taskId Task to resume
     */
    function resumeTask(
        uint256 _taskId
    ) external onlyTaskCreator(_taskId) taskExists(_taskId) {
        Task storage task = tasks[_taskId];
        require(task.status == TaskStatus.PAUSED, "Task not paused");

        task.status = TaskStatus.ACTIVE;
        emit TaskStatusChanged(_taskId, TaskStatus.PAUSED, TaskStatus.ACTIVE);
    }

    // ============ Internal Functions ============

    /**
     * @notice Check if task condition is met
     * @param _condition Condition to check
     * @return bool Whether condition is satisfied
     */
    function _checkCondition(
        Condition memory _condition
    ) internal returns (bool) {
        if (conditionChecker == address(0)) {
            // No condition checker - always allow
            return true;
        }

        (bool success, bytes memory result) = conditionChecker.call(
            abi.encodeWithSignature(
                "checkCondition(uint8,bytes)",
                uint8(_condition.conditionType),
                _condition.conditionData
            )
        );

        if (!success) {
            return false;
        }

        return abi.decode(result, (bool));
    }

    /**
     * @notice Execute all task actions
     * @param _taskId Task ID for tracking
     * @param _actions Array of actions to execute
     * @return bool Whether all actions succeeded
     */
    function _executeActions(
        uint256 _taskId,
        Action[] storage _actions
    ) internal returns (bool) {
        if (actionRouter == address(0)) {
            // No action router configured
            return false;
        }

        for (uint256 i = 0; i < _actions.length; i++) {
            Action storage action = _actions[i];

            (bool success, ) = actionRouter.call(
                abi.encodeWithSignature(
                    "routeAction(uint256,address,bytes4,bytes,uint256)",
                    _taskId,
                    action.protocol,
                    action.selector,
                    action.params,
                    action.value
                )
            );

            if (!success) {
                return false;
            }
        }

        return true;
    }

    // ============ View Functions ============

    /**
     * @notice Get all actions for a task
     * @param _taskId Task ID
     * @return Action[] Array of actions
     */
    function getTaskActions(uint256 _taskId) external view returns (Action[] memory) {
        return tasks[_taskId].actions;
    }

    /**
     * @notice Get executable tasks
     * @param _limit Maximum number of tasks to return
     * @return Task[] Array of executable tasks
     */
    function getExecutableTasks(
        uint256 _limit
    ) external view returns (Task[] memory) {
        uint256 count = 0;
        Task[] memory result = new Task[](_limit);

        for (uint256 i = 0; i < nextTaskId && count < _limit; i++) {
            Task storage task = tasks[i];

            if (
                task.status == TaskStatus.ACTIVE &&
                (task.expiresAt == 0 || block.timestamp <= task.expiresAt) &&
                (task.maxExecutions == 0 || task.executionCount < task.maxExecutions)
            ) {
                // Check recurring interval
                if (task.recurringInterval > 0 && task.lastExecutionTime > 0) {
                    if (block.timestamp < task.lastExecutionTime + task.recurringInterval) {
                        continue;
                    }
                }

                result[count] = task;
                count++;
            }
        }

        // Trim array to actual size
        assembly {
            mstore(result, count)
        }

        return result;
    }

    /**
     * @notice Get tasks created by an address
     * @param _creator Creator address
     * @return uint256[] Array of task IDs
     */
    function getCreatorTasks(address _creator) external view returns (uint256[] memory) {
        return creatorTasks[_creator];
    }

    /**
     * @notice Get tasks executed by an executor
     * @param _executor Executor address
     * @return uint256[] Array of task IDs
     */
    function getExecutorHistory(address _executor) external view returns (uint256[] memory) {
        return executorHistory[_executor];
    }

    /**
     * @notice Check if a task can be executed now
     * @param _taskId Task ID
     * @return bool Whether task is executable
     */
    function isTaskExecutable(uint256 _taskId) external view returns (bool) {
        Task storage task = tasks[_taskId];

        if (task.status != TaskStatus.ACTIVE) {
            return false;
        }

        if (task.expiresAt != 0 && block.timestamp > task.expiresAt) {
            return false;
        }

        if (task.maxExecutions > 0 && task.executionCount >= task.maxExecutions) {
            return false;
        }

        if (task.recurringInterval > 0 && task.lastExecutionTime > 0) {
            if (block.timestamp < task.lastExecutionTime + task.recurringInterval) {
                return false;
            }
        }

        return true;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set condition checker contract
     * @param _conditionChecker Address of condition checker
     */
    function setConditionChecker(address _conditionChecker) external onlyOwner {
        conditionChecker = _conditionChecker;
    }

    /**
     * @notice Set action router contract
     * @param _actionRouter Address of action router
     */
    function setActionRouter(address _actionRouter) external onlyOwner {
        actionRouter = _actionRouter;
    }

    /**
     * @notice Set executor manager contract
     * @param _executorManager Address of executor manager
     */
    function setExecutorManager(address _executorManager) external onlyOwner {
        executorManager = _executorManager;
    }

    /**
     * @notice Set payment escrow contract
     * @param _paymentEscrow Address of payment escrow
     */
    function setPaymentEscrow(address _paymentEscrow) external onlyOwner {
        paymentEscrow = _paymentEscrow;
    }

    /**
     * @notice Set reputation system contract
     * @param _reputationSystem Address of reputation system
     */
    function setReputationSystem(address _reputationSystem) external onlyOwner {
        reputationSystem = _reputationSystem;
    }

    /**
     * @notice Approve a protocol for task creation
     * @param _protocol Protocol address
     */
    function approveProtocol(address _protocol) external onlyOwner {
        approvedProtocols[_protocol] = true;
        emit ProtocolApproved(_protocol);
    }

    /**
     * @notice Revoke protocol approval
     * @param _protocol Protocol address
     */
    function revokeProtocol(address _protocol) external onlyOwner {
        approvedProtocols[_protocol] = false;
        emit ProtocolRevoked(_protocol);
    }

    /**
     * @notice Batch approve multiple protocols
     * @param _protocols Array of protocol addresses
     */
    function batchApproveProtocols(address[] calldata _protocols) external onlyOwner {
        for (uint256 i = 0; i < _protocols.length; i++) {
            approvedProtocols[_protocols[i]] = true;
            emit ProtocolApproved(_protocols[i]);
        }
    }

    /**
     * @notice Update platform fee
     * @param _feePercentage New fee in basis points
     */
    function setPlatformFee(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= MAX_PLATFORM_FEE, "Fee too high");
        platformFeePercentage = _feePercentage;
    }
}
