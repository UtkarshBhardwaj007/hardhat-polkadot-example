// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReputationSystem
 * @notice Tracks executor reputation and provides tiered benefits
 * @dev Reputation influences fee multipliers and task access
 */
contract ReputationSystem is Ownable {

    // ============ Structures ============

    /**
     * @notice Reputation data for each executor (max 12 fields)
     * @param executor Address of the executor
     * @param totalTasks Total tasks executed
     * @param successfulTasks Successfully completed tasks
     * @param failedTasks Failed task attempts
     * @param totalRewardsEarned Total rewards earned (in wei)
     * @param reputationScore Current reputation score (0-10000)
     * @param tier Current reputation tier (0-4)
     * @param lastUpdateTime Last reputation update timestamp
     */
    struct Reputation {
        address executor;
        uint256 totalTasks;
        uint256 successfulTasks;
        uint256 failedTasks;
        uint256 totalRewardsEarned;
        uint256 reputationScore;
        uint8 tier;
        uint256 lastUpdateTime;
    }

    /**
     * @notice Reputation tier thresholds
     */
    enum Tier {
        ROOKIE,      // 0-10 tasks
        BRONZE,      // 11-100 tasks, >80% success
        SILVER,      // 101-500 tasks, >90% success
        GOLD,        // 501-2000 tasks, >95% success
        DIAMOND      // 2001+ tasks, >98% success
    }

    // ============ State Variables ============

    /// @notice Mapping from executor to reputation
    mapping(address => Reputation) public reputations;

    /// @notice Authorized contracts that can update reputation
    mapping(address => bool) public authorizedUpdaters;

    /// @notice Fee multipliers per tier (basis points, 10000 = 100%)
    mapping(uint8 => uint256) public tierMultipliers;

    /// @notice Total executors with reputation
    uint256 public totalExecutors;

    // ============ Events ============

    event ReputationUpdated(
        address indexed executor,
        uint256 reputationScore,
        uint8 tier
    );

    event SuccessRecorded(
        address indexed executor,
        uint256 indexed taskId,
        uint256 reward
    );

    event FailureRecorded(
        address indexed executor,
        uint256 indexed taskId
    );

    event TierPromoted(address indexed executor, uint8 newTier);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {
        // Set default tier multipliers
        tierMultipliers[uint8(Tier.ROOKIE)] = 10000;   // 100% (no bonus)
        tierMultipliers[uint8(Tier.BRONZE)] = 10500;   // 105% (+5% bonus)
        tierMultipliers[uint8(Tier.SILVER)] = 11000;   // 110% (+10% bonus)
        tierMultipliers[uint8(Tier.GOLD)] = 11500;     // 115% (+15% bonus)
        tierMultipliers[uint8(Tier.DIAMOND)] = 12000;  // 120% (+20% bonus)
    }

    // ============ Core Functions ============

    /**
     * @notice Record successful task execution
     * @param _executor Executor address
     * @param _taskId Task ID
     * @param _reward Reward amount earned
     */
    function recordSuccess(
        address _executor,
        uint256 _taskId,
        uint256 _reward
    ) external onlyAuthorized {
        Reputation storage rep = reputations[_executor];

        // Initialize if first time
        if (rep.executor == address(0)) {
            rep.executor = _executor;
            totalExecutors++;
        }

        rep.totalTasks++;
        rep.successfulTasks++;
        rep.totalRewardsEarned += _reward;
        rep.lastUpdateTime = block.timestamp;

        // Update reputation score
        _updateReputationScore(rep);

        // Check for tier promotion
        _updateTier(rep);

        emit SuccessRecorded(_executor, _taskId, _reward);
        emit ReputationUpdated(_executor, rep.reputationScore, rep.tier);
    }

    /**
     * @notice Record failed task execution
     * @param _executor Executor address
     * @param _taskId Task ID
     */
    function recordFailure(
        address _executor,
        uint256 _taskId
    ) external onlyAuthorized {
        Reputation storage rep = reputations[_executor];

        // Initialize if first time
        if (rep.executor == address(0)) {
            rep.executor = _executor;
            totalExecutors++;
        }

        rep.totalTasks++;
        rep.failedTasks++;
        rep.lastUpdateTime = block.timestamp;

        // Update reputation score (will decrease)
        _updateReputationScore(rep);

        // Check for tier demotion
        _updateTier(rep);

        emit FailureRecorded(_executor, _taskId);
        emit ReputationUpdated(_executor, rep.reputationScore, rep.tier);
    }

    /**
     * @notice Calculate reward with reputation multiplier
     * @param _executor Executor address
     * @param _baseReward Base reward amount
     * @return uint256 Reward with multiplier applied
     */
    function calculateRewardWithMultiplier(
        address _executor,
        uint256 _baseReward
    ) external view returns (uint256) {
        Reputation storage rep = reputations[_executor];
        uint256 multiplier = tierMultipliers[rep.tier];

        return (_baseReward * multiplier) / 10000;
    }

    // ============ Internal Functions ============

    /**
     * @notice Update reputation score based on success rate
     * @param _rep Reputation struct reference
     */
    function _updateReputationScore(Reputation storage _rep) internal {
        if (_rep.totalTasks == 0) {
            _rep.reputationScore = 0;
            return;
        }

        // Calculate success rate (0-10000 scale)
        uint256 successRate = (_rep.successfulTasks * 10000) / _rep.totalTasks;

        // Weight recent performance more heavily
        // Score = (successRate * 0.7) + (volume bonus * 0.3)
        uint256 volumeBonus = _calculateVolumeBonus(_rep.totalTasks);

        _rep.reputationScore = (successRate * 70 + volumeBonus * 30) / 100;
    }

    /**
     * @notice Calculate volume bonus based on total tasks
     * @param _totalTasks Total tasks executed
     * @return uint256 Volume bonus (0-10000)
     */
    function _calculateVolumeBonus(uint256 _totalTasks) internal pure returns (uint256) {
        if (_totalTasks >= 2000) return 10000;
        if (_totalTasks >= 500) return 7500;
        if (_totalTasks >= 100) return 5000;
        if (_totalTasks >= 10) return 2500;
        return 1000;
    }

    /**
     * @notice Update executor tier based on performance
     * @param _rep Reputation struct reference
     */
    function _updateTier(Reputation storage _rep) internal {
        uint8 oldTier = _rep.tier;
        uint8 newTier = _calculateTier(_rep);

        if (newTier != oldTier) {
            _rep.tier = newTier;
            emit TierPromoted(_rep.executor, newTier);
        }
    }

    /**
     * @notice Calculate appropriate tier for executor
     * @param _rep Reputation data
     * @return uint8 Tier level
     */
    function _calculateTier(Reputation storage _rep) internal view returns (uint8) {
        uint256 totalTasks = _rep.totalTasks;
        uint256 successRate = totalTasks > 0
            ? (_rep.successfulTasks * 10000) / totalTasks
            : 0;

        // DIAMOND: 2001+ tasks, >98% success
        if (totalTasks > 2000 && successRate >= 9800) {
            return uint8(Tier.DIAMOND);
        }

        // GOLD: 501-2000 tasks, >95% success
        if (totalTasks > 500 && successRate >= 9500) {
            return uint8(Tier.GOLD);
        }

        // SILVER: 101-500 tasks, >90% success
        if (totalTasks > 100 && successRate >= 9000) {
            return uint8(Tier.SILVER);
        }

        // BRONZE: 11-100 tasks, >80% success
        if (totalTasks > 10 && successRate >= 8000) {
            return uint8(Tier.BRONZE);
        }

        // ROOKIE: Default
        return uint8(Tier.ROOKIE);
    }

    // ============ View Functions ============

    /**
     * @notice Get executor reputation
     * @param _executor Executor address
     * @return Reputation Reputation data
     */
    function getReputation(address _executor) external view returns (Reputation memory) {
        return reputations[_executor];
    }

    /**
     * @notice Get executor success rate
     * @param _executor Executor address
     * @return uint256 Success rate in basis points (10000 = 100%)
     */
    function getSuccessRate(address _executor) external view returns (uint256) {
        Reputation storage rep = reputations[_executor];

        if (rep.totalTasks == 0) {
            return 0;
        }

        return (rep.successfulTasks * 10000) / rep.totalTasks;
    }

    /**
     * @notice Get executor tier name
     * @param _executor Executor address
     * @return string Tier name
     */
    function getTierName(address _executor) external view returns (string memory) {
        uint8 tier = reputations[_executor].tier;

        if (tier == uint8(Tier.DIAMOND)) return "DIAMOND";
        if (tier == uint8(Tier.GOLD)) return "GOLD";
        if (tier == uint8(Tier.SILVER)) return "SILVER";
        if (tier == uint8(Tier.BRONZE)) return "BRONZE";
        return "ROOKIE";
    }

    /**
     * @notice Check if executor qualifies for tier
     * @param _executor Executor address
     * @param _tier Tier to check
     * @return bool Whether executor qualifies
     */
    function qualifiesForTier(address _executor, uint8 _tier) external view returns (bool) {
        Reputation storage rep = reputations[_executor];
        return _calculateTier(rep) >= _tier;
    }

    // ============ Admin Functions ============

    /**
     * @notice Authorize contract to update reputation
     * @param _updater Address to authorize (e.g., TaskRegistry)
     */
    function authorizeUpdater(address _updater) external onlyOwner {
        authorizedUpdaters[_updater] = true;
    }

    /**
     * @notice Revoke updater authorization
     * @param _updater Address to revoke
     */
    function revokeUpdater(address _updater) external onlyOwner {
        authorizedUpdaters[_updater] = false;
    }

    /**
     * @notice Set tier multiplier
     * @param _tier Tier level
     * @param _multiplier Multiplier in basis points
     */
    function setTierMultiplier(uint8 _tier, uint256 _multiplier) external onlyOwner {
        require(_tier <= uint8(Tier.DIAMOND), "Invalid tier");
        require(_multiplier >= 10000 && _multiplier <= 15000, "Invalid multiplier");

        tierMultipliers[_tier] = _multiplier;
    }

    /**
     * @notice Manually adjust executor reputation (emergency only)
     * @param _executor Executor address
     * @param _score New reputation score
     */
    function manuallySetReputation(
        address _executor,
        uint256 _score
    ) external onlyOwner {
        require(_score <= 10000, "Invalid score");

        Reputation storage rep = reputations[_executor];
        rep.reputationScore = _score;

        _updateTier(rep);

        emit ReputationUpdated(_executor, _score, rep.tier);
    }

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        require(
            authorizedUpdaters[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }
}
