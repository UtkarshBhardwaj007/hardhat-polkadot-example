// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ExecutorManager
 * @notice Manages executor registrations, execution locks, and access control
 * @dev Prevents double-execution and manages executor lifecycle
 */
contract ExecutorManager is Ownable, ReentrancyGuard {

    // ============ Structures ============

    /**
     * @notice Executor profile (max 12 fields for Substrate compatibility)
     * @param executor Address of the executor
     * @param isRegistered Whether executor is registered
     * @param isBlacklisted Whether executor is banned
     * @param registeredAt Timestamp of registration
     * @param totalExecutions Total number of executions attempted
     * @param successfulExecutions Number of successful executions
     * @param failedExecutions Number of failed executions
     */
    struct Executor {
        address executor;
        bool isRegistered;
        bool isBlacklisted;
        uint256 registeredAt;
        uint256 totalExecutions;
        uint256 successfulExecutions;
        uint256 failedExecutions;
    }

    /**
     * @notice Temporary lock on task execution
     * @param executor Address holding the lock
     * @param lockedAt Timestamp when locked
     * @param taskId Task being executed
     */
    struct ExecutionLock {
        address executor;
        uint256 lockedAt;
        uint256 taskId;
    }

    // ============ State Variables ============

    /// @notice Mapping from executor address to profile
    mapping(address => Executor) public executors;

    /// @notice Mapping from task ID to current lock
    mapping(uint256 => ExecutionLock) public taskLocks;

    /// @notice Task registry contract
    address public taskRegistry;

    /// @notice Duration of execution lock (prevents front-running)
    uint256 public executionLockDuration = 30 seconds;

    /// @notice Minimum time between registrations from same address
    uint256 public registrationCooldown = 1 days;

    /// @notice Total registered executors
    uint256 public totalExecutors;

    // ============ Events ============

    event ExecutorRegistered(address indexed executor, uint256 timestamp);
    event ExecutorBlacklisted(address indexed executor, string reason);
    event ExecutorUnblacklisted(address indexed executor);
    event TaskLocked(uint256 indexed taskId, address indexed executor);
    event TaskUnlocked(uint256 indexed taskId);
    event ExecutionAttempted(
        uint256 indexed taskId,
        address indexed executor,
        bool success
    );

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(executors[msg.sender].isRegistered, "Not registered");
        _;
    }

    modifier notBlacklisted() {
        require(!executors[msg.sender].isBlacklisted, "Blacklisted");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Core Functions ============

    /**
     * @notice Register as an executor
     */
    function registerExecutor() external {
        require(!executors[msg.sender].isRegistered, "Already registered");

        executors[msg.sender] = Executor({
            executor: msg.sender,
            isRegistered: true,
            isBlacklisted: false,
            registeredAt: block.timestamp,
            totalExecutions: 0,
            successfulExecutions: 0,
            failedExecutions: 0
        });

        totalExecutors++;

        emit ExecutorRegistered(msg.sender, block.timestamp);
    }

    /**
     * @notice Attempt to execute a task
     * @param _taskId Task ID to execute
     */
    function attemptExecute(
        uint256 _taskId
    ) external onlyRegistered notBlacklisted nonReentrant {
        require(taskRegistry != address(0), "Registry not set");

        // Check if task is currently locked
        ExecutionLock storage lock = taskLocks[_taskId];

        if (lock.executor != address(0)) {
            // Task is locked - check if lock has expired
            if (block.timestamp <= lock.lockedAt + executionLockDuration) {
                require(lock.executor == msg.sender, "Task locked by another executor");
            } else {
                // Lock expired - unlock it
                emit TaskUnlocked(_taskId);
            }
        }

        // Lock task for this executor
        taskLocks[_taskId] = ExecutionLock({
            executor: msg.sender,
            lockedAt: block.timestamp,
            taskId: _taskId
        });

        emit TaskLocked(_taskId, msg.sender);

        // Execute task via registry
        (bool success, bytes memory returnData) = taskRegistry.call(
            abi.encodeWithSignature(
                "executeTask(uint256,address)",
                _taskId,
                msg.sender
            )
        );

        // Update executor stats
        Executor storage executor = executors[msg.sender];
        executor.totalExecutions++;

        bool executionSuccess = false;
        if (success && returnData.length > 0) {
            executionSuccess = abi.decode(returnData, (bool));
        }

        if (executionSuccess) {
            executor.successfulExecutions++;
        } else {
            executor.failedExecutions++;
        }

        emit ExecutionAttempted(_taskId, msg.sender, executionSuccess);

        // Unlock task
        delete taskLocks[_taskId];
        emit TaskUnlocked(_taskId);
    }

    /**
     * @notice Batch execute multiple tasks
     * @param _taskIds Array of task IDs
     */
    function batchExecute(
        uint256[] calldata _taskIds
    ) external onlyRegistered notBlacklisted nonReentrant {
        require(_taskIds.length > 0, "No tasks provided");
        require(_taskIds.length <= 10, "Too many tasks");

        for (uint256 i = 0; i < _taskIds.length; i++) {
            // Try to execute each task
            // Note: We use try-catch pattern here to prevent one failure from blocking others
            try this.attemptExecute(_taskIds[i]) {
                // Success handled in attemptExecute
            } catch {
                // Continue to next task
                continue;
            }
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check if executor can execute tasks
     * @param _executor Executor address
     * @return bool Whether executor can execute
     */
    function canExecute(address _executor) external view returns (bool) {
        return executors[_executor].isRegistered &&
               !executors[_executor].isBlacklisted;
    }

    /**
     * @notice Get executor profile
     * @param _executor Executor address
     * @return Executor Profile data
     */
    function getExecutor(address _executor) external view returns (Executor memory) {
        return executors[_executor];
    }

    /**
     * @notice Get executor success rate
     * @param _executor Executor address
     * @return uint256 Success rate in basis points (10000 = 100%)
     */
    function getSuccessRate(address _executor) external view returns (uint256) {
        Executor storage executor = executors[_executor];

        if (executor.totalExecutions == 0) {
            return 0;
        }

        return (executor.successfulExecutions * 10000) / executor.totalExecutions;
    }

    /**
     * @notice Check if task is currently locked
     * @param _taskId Task ID
     * @return bool Whether task is locked
     * @return address Executor holding lock (if any)
     */
    function isTaskLocked(uint256 _taskId) external view returns (bool, address) {
        ExecutionLock storage lock = taskLocks[_taskId];

        if (lock.executor == address(0)) {
            return (false, address(0));
        }

        if (block.timestamp > lock.lockedAt + executionLockDuration) {
            return (false, address(0)); // Lock expired
        }

        return (true, lock.executor);
    }

    /**
     * @notice Get lock info for a task
     * @param _taskId Task ID
     * @return ExecutionLock Lock data
     */
    function getTaskLock(uint256 _taskId) external view returns (ExecutionLock memory) {
        return taskLocks[_taskId];
    }

    // ============ Admin Functions ============

    /**
     * @notice Set task registry address
     * @param _taskRegistry Task registry contract
     */
    function setTaskRegistry(address _taskRegistry) external onlyOwner {
        require(_taskRegistry != address(0), "Invalid registry");
        taskRegistry = _taskRegistry;
    }

    /**
     * @notice Update execution lock duration
     * @param _duration New duration in seconds
     */
    function setExecutionLockDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0 && _duration <= 5 minutes, "Invalid duration");
        executionLockDuration = _duration;
    }

    /**
     * @notice Blacklist an executor
     * @param _executor Executor to blacklist
     * @param _reason Reason for blacklisting
     */
    function blacklistExecutor(
        address _executor,
        string calldata _reason
    ) external onlyOwner {
        require(executors[_executor].isRegistered, "Executor not registered");
        executors[_executor].isBlacklisted = true;
        emit ExecutorBlacklisted(_executor, _reason);
    }

    /**
     * @notice Remove executor from blacklist
     * @param _executor Executor to unblacklist
     */
    function unblacklistExecutor(address _executor) external onlyOwner {
        executors[_executor].isBlacklisted = false;
        emit ExecutorUnblacklisted(_executor);
    }

    /**
     * @notice Emergency unlock a task
     * @param _taskId Task to unlock
     */
    function emergencyUnlock(uint256 _taskId) external onlyOwner {
        delete taskLocks[_taskId];
        emit TaskUnlocked(_taskId);
    }
}
