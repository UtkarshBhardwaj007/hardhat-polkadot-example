// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PaymentEscrow
 * @notice Holds task rewards in escrow and distributes them to executors
 * @dev Manages platform fees and refunds for cancelled tasks
 */
contract PaymentEscrow is Ownable, ReentrancyGuard {

    // ============ Structures ============

    /**
     * @notice Escrow data for each task (max 12 fields for Substrate compatibility)
     * @param taskId Unique task identifier
     * @param creator Address that funded the task
     * @param totalLocked Total amount locked in escrow
     * @param amountPaid Amount already paid to executors
     * @param amountRefunded Amount refunded to creator
     * @param platformFeesCollected Platform fees collected
     * @param isActive Whether escrow is active
     */
    struct EscrowData {
        uint256 taskId;
        address creator;
        uint256 totalLocked;
        uint256 amountPaid;
        uint256 amountRefunded;
        uint256 platformFeesCollected;
        bool isActive;
    }

    // ============ State Variables ============

    /// @notice Mapping from task ID to escrow data
    mapping(uint256 => EscrowData) public escrows;

    /// @notice Task registry that can manage escrows
    address public taskRegistry;

    /// @notice Platform fee recipient
    address public feeRecipient;

    /// @notice Total platform fees collected (all tasks)
    uint256 public totalPlatformFees;

    // ============ Events ============

    event FundsLocked(
        uint256 indexed taskId,
        address indexed creator,
        uint256 amount
    );

    event PaymentReleased(
        uint256 indexed taskId,
        address indexed executor,
        uint256 reward,
        uint256 platformFee
    );

    event FundsRefunded(
        uint256 indexed taskId,
        address indexed creator,
        uint256 amount
    );

    event FundsAdded(
        uint256 indexed taskId,
        uint256 amount
    );

    event FeesWithdrawn(address indexed recipient, uint256 amount);

    // ============ Modifiers ============

    modifier onlyTaskRegistry() {
        require(msg.sender == taskRegistry, "Only task registry");
        _;
    }

    // ============ Constructor ============

    constructor(address _feeRecipient) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    // ============ Core Functions ============

    /**
     * @notice Lock funds for a task
     * @param _taskId Task identifier
     * @param _creator Address funding the task
     * @param _amount Amount to lock
     */
    function lockFunds(
        uint256 _taskId,
        address _creator,
        uint256 _amount
    ) external payable onlyTaskRegistry nonReentrant {
        require(msg.value == _amount, "Amount mismatch");
        require(!escrows[_taskId].isActive, "Escrow already exists");

        escrows[_taskId] = EscrowData({
            taskId: _taskId,
            creator: _creator,
            totalLocked: _amount,
            amountPaid: 0,
            amountRefunded: 0,
            platformFeesCollected: 0,
            isActive: true
        });

        emit FundsLocked(_taskId, _creator, _amount);
    }

    /**
     * @notice Release payment to executor
     * @param _taskId Task identifier
     * @param _executor Executor to pay
     * @param _reward Base reward amount
     * @param _platformFeePercentage Platform fee in basis points (e.g., 100 = 1%)
     */
    function releasePayment(
        uint256 _taskId,
        address _executor,
        uint256 _reward,
        uint256 _platformFeePercentage
    ) external onlyTaskRegistry nonReentrant {
        EscrowData storage escrow = escrows[_taskId];

        require(escrow.isActive, "Escrow not active");
        require(_executor != address(0), "Invalid executor");

        // Calculate platform fee
        uint256 platformFee = (_reward * _platformFeePercentage) / 10000;
        uint256 executorPayout = _reward - platformFee;

        // Check sufficient balance
        uint256 availableBalance = escrow.totalLocked - escrow.amountPaid - escrow.amountRefunded;
        require(availableBalance >= _reward, "Insufficient escrow balance");

        // Update escrow state
        escrow.amountPaid += _reward;
        escrow.platformFeesCollected += platformFee;
        totalPlatformFees += platformFee;

        // Transfer to executor
        (bool success, ) = _executor.call{value: executorPayout}("");
        require(success, "Transfer to executor failed");

        emit PaymentReleased(_taskId, _executor, executorPayout, platformFee);
    }

    /**
     * @notice Refund remaining funds to creator
     * @param _taskId Task identifier
     * @param _recipient Refund recipient
     * @param _amount Amount to refund
     */
    function refund(
        uint256 _taskId,
        address _recipient,
        uint256 _amount
    ) external onlyTaskRegistry nonReentrant {
        EscrowData storage escrow = escrows[_taskId];

        require(escrow.isActive, "Escrow not active");
        require(_recipient != address(0), "Invalid recipient");

        // Check available balance
        uint256 availableBalance = escrow.totalLocked - escrow.amountPaid - escrow.amountRefunded;
        require(availableBalance >= _amount, "Insufficient balance for refund");

        // Update escrow state
        escrow.amountRefunded += _amount;

        // Transfer refund
        (bool success, ) = _recipient.call{value: _amount}("");
        require(success, "Refund transfer failed");

        emit FundsRefunded(_taskId, _recipient, _amount);
    }

    /**
     * @notice Add additional funds to existing escrow
     * @param _taskId Task identifier
     * @param _amount Amount to add
     */
    function addFunds(
        uint256 _taskId,
        uint256 _amount
    ) external payable onlyTaskRegistry nonReentrant {
        EscrowData storage escrow = escrows[_taskId];

        require(escrow.isActive, "Escrow not active");
        require(msg.value == _amount, "Amount mismatch");

        escrow.totalLocked += _amount;

        emit FundsAdded(_taskId, _amount);
    }

    /**
     * @notice Withdraw collected platform fees
     * @param _amount Amount to withdraw (0 = all)
     */
    function withdrawPlatformFees(uint256 _amount) external onlyOwner nonReentrant {
        uint256 withdrawAmount = _amount == 0 ? totalPlatformFees : _amount;

        require(withdrawAmount <= totalPlatformFees, "Insufficient fees");
        require(withdrawAmount <= address(this).balance, "Insufficient contract balance");

        totalPlatformFees -= withdrawAmount;

        (bool success, ) = feeRecipient.call{value: withdrawAmount}("");
        require(success, "Fee withdrawal failed");

        emit FeesWithdrawn(feeRecipient, withdrawAmount);
    }

    // ============ View Functions ============

    /**
     * @notice Get escrow data for a task
     * @param _taskId Task identifier
     * @return EscrowData Escrow information
     */
    function getEscrow(uint256 _taskId) external view returns (EscrowData memory) {
        return escrows[_taskId];
    }

    /**
     * @notice Get available balance in escrow
     * @param _taskId Task identifier
     * @return uint256 Available balance
     */
    function getAvailableBalance(uint256 _taskId) external view returns (uint256) {
        EscrowData storage escrow = escrows[_taskId];
        return escrow.totalLocked - escrow.amountPaid - escrow.amountRefunded;
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
     * @notice Update fee recipient
     * @param _feeRecipient New fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid recipient");
        feeRecipient = _feeRecipient;
    }

    // Allow receiving ETH
    receive() external payable {}
}
