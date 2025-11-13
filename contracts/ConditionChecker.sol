// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ConditionChecker
 * @notice Evaluates various conditions for task execution
 * @dev Supports price feeds, time-based, balance-based, and custom oracle conditions
 */
contract ConditionChecker is Ownable {

    // ============ Interfaces ============

    /**
     * @notice Chainlink-style price feed interface
     */
    interface AggregatorV3Interface {
        function latestRoundData() external view returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

        function decimals() external view returns (uint8);
    }

    // ============ State Variables ============

    /// @notice Price feeds for different tokens (Chainlink or compatible)
    mapping(address => AggregatorV3Interface) public priceFeeds;

    /// @notice Approved custom oracle contracts
    mapping(address => bool) public approvedOracles;

    /// @notice Maximum staleness for price data (in seconds)
    uint256 public maxPriceStaleness = 1 hours;

    // ============ Events ============

    event PriceFeedSet(address indexed token, address indexed priceFeed);
    event OracleApproved(address indexed oracle);
    event OracleRevoked(address indexed oracle);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Main Entry Point ============

    /**
     * @notice Check if a condition is met
     * @param _conditionType Type of condition (0-5)
     * @param _conditionData ABI-encoded condition parameters
     * @return bool Whether condition is satisfied
     */
    function checkCondition(
        uint8 _conditionType,
        bytes calldata _conditionData
    ) external view returns (bool) {

        if (_conditionType == 0) {
            // ALWAYS - always returns true
            return true;
        }

        if (_conditionType == 1) {
            // PRICE_THRESHOLD
            return _checkPriceThreshold(_conditionData);
        }

        if (_conditionType == 2) {
            // TIME_BASED
            return _checkTimeBased(_conditionData);
        }

        if (_conditionType == 3) {
            // BALANCE_THRESHOLD
            return _checkBalanceThreshold(_conditionData);
        }

        if (_conditionType == 4) {
            // CUSTOM_ORACLE
            return _checkCustomOracle(_conditionData);
        }

        if (_conditionType == 5) {
            // MULTI_CONDITION
            return _checkMultiCondition(_conditionData);
        }

        revert("Unknown condition type");
    }

    // ============ Condition Implementations ============

    /**
     * @notice Check if asset price meets threshold
     * @param _data Encoded: (token, targetPrice, isGreaterThan)
     * @return bool Whether price condition is met
     */
    function _checkPriceThreshold(
        bytes calldata _data
    ) internal view returns (bool) {
        (
            address token,
            uint256 targetPrice,
            bool isGreaterThan
        ) = abi.decode(_data, (address, uint256, bool));

        AggregatorV3Interface priceFeed = priceFeeds[token];
        require(address(priceFeed) != address(0), "No price feed for token");

        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate price data freshness
        require(price > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale price data");
        require(block.timestamp - updatedAt <= maxPriceStaleness, "Price too old");

        uint256 currentPrice = uint256(price);

        if (isGreaterThan) {
            return currentPrice >= targetPrice;
        } else {
            return currentPrice <= targetPrice;
        }
    }

    /**
     * @notice Check if current time meets threshold
     * @param _data Encoded: (targetTimestamp)
     * @return bool Whether time condition is met
     */
    function _checkTimeBased(
        bytes calldata _data
    ) internal view returns (bool) {
        uint256 targetTime = abi.decode(_data, (uint256));
        return block.timestamp >= targetTime;
    }

    /**
     * @notice Check if account balance meets threshold
     * @param _data Encoded: (account, token, threshold, isGreaterThan)
     * @return bool Whether balance condition is met
     */
    function _checkBalanceThreshold(
        bytes calldata _data
    ) internal view returns (bool) {
        (
            address account,
            address token,
            uint256 threshold,
            bool isGreaterThan
        ) = abi.decode(_data, (address, address, uint256, bool));

        uint256 balance;

        if (token == address(0)) {
            // Native token (ETH/MATIC/etc.)
            balance = account.balance;
        } else {
            // ERC20 token
            balance = IERC20(token).balanceOf(account);
        }

        if (isGreaterThan) {
            return balance >= threshold;
        } else {
            return balance <= threshold;
        }
    }

    /**
     * @notice Check custom oracle condition
     * @param _data Encoded: (oracleAddress, oracleCallData)
     * @return bool Whether oracle condition is met
     */
    function _checkCustomOracle(
        bytes calldata _data
    ) internal view returns (bool) {
        (
            address oracle,
            bytes memory oracleCall
        ) = abi.decode(_data, (address, bytes));

        require(approvedOracles[oracle], "Oracle not approved");

        (bool success, bytes memory result) = oracle.staticcall(oracleCall);
        require(success, "Oracle call failed");

        return abi.decode(result, (bool));
    }

    /**
     * @notice Check multiple conditions with AND/OR logic
     * @param _data Encoded: (useAnd, conditions[])
     * @return bool Whether multi-condition is met
     */
    function _checkMultiCondition(
        bytes calldata _data
    ) internal view returns (bool) {
        (
            bool useAnd,  // true = AND, false = OR
            bytes[] memory conditions
        ) = abi.decode(_data, (bool, bytes[]));

        if (useAnd) {
            // All conditions must be true
            for (uint256 i = 0; i < conditions.length; i++) {
                (uint8 condType, bytes memory condData) =
                    abi.decode(conditions[i], (uint8, bytes));

                if (!this.checkCondition(condType, condData)) {
                    return false;
                }
            }
            return true;
        } else {
            // At least one condition must be true
            for (uint256 i = 0; i < conditions.length; i++) {
                (uint8 condType, bytes memory condData) =
                    abi.decode(conditions[i], (uint8, bytes));

                if (this.checkCondition(condType, condData)) {
                    return true;
                }
            }
            return false;
        }
    }

    // ============ Helper View Functions ============

    /**
     * @notice Get current price for a token
     * @param _token Token address
     * @return price Current price
     * @return decimals Price decimals
     */
    function getCurrentPrice(address _token) external view returns (uint256 price, uint8 decimals) {
        AggregatorV3Interface priceFeed = priceFeeds[_token];
        require(address(priceFeed) != address(0), "No price feed");

        (
            ,
            int256 priceInt,
            ,
            uint256 updatedAt,

        ) = priceFeed.latestRoundData();

        require(priceInt > 0, "Invalid price");
        require(block.timestamp - updatedAt <= maxPriceStaleness, "Price too old");

        price = uint256(priceInt);
        decimals = priceFeed.decimals();
    }

    /**
     * @notice Preview if a condition would be met
     * @param _conditionType Type of condition
     * @param _conditionData Encoded condition data
     * @return bool Whether condition is met
     * @return string Reason if not met (for debugging)
     */
    function previewCondition(
        uint8 _conditionType,
        bytes calldata _conditionData
    ) external view returns (bool, string memory) {
        try this.checkCondition(_conditionType, _conditionData) returns (bool result) {
            if (result) {
                return (true, "Condition met");
            } else {
                return (false, "Condition not met");
            }
        } catch Error(string memory reason) {
            return (false, reason);
        } catch {
            return (false, "Unknown error");
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Set price feed for a token
     * @param _token Token address
     * @param _priceFeed Price feed address (Chainlink aggregator)
     */
    function setPriceFeed(
        address _token,
        address _priceFeed
    ) external onlyOwner {
        require(_token != address(0), "Invalid token");
        require(_priceFeed != address(0), "Invalid price feed");

        priceFeeds[_token] = AggregatorV3Interface(_priceFeed);
        emit PriceFeedSet(_token, _priceFeed);
    }

    /**
     * @notice Batch set multiple price feeds
     * @param _tokens Array of token addresses
     * @param _priceFeeds Array of price feed addresses
     */
    function batchSetPriceFeeds(
        address[] calldata _tokens,
        address[] calldata _priceFeeds
    ) external onlyOwner {
        require(_tokens.length == _priceFeeds.length, "Length mismatch");

        for (uint256 i = 0; i < _tokens.length; i++) {
            priceFeeds[_tokens[i]] = AggregatorV3Interface(_priceFeeds[i]);
            emit PriceFeedSet(_tokens[i], _priceFeeds[i]);
        }
    }

    /**
     * @notice Approve a custom oracle
     * @param _oracle Oracle contract address
     */
    function approveOracle(address _oracle) external onlyOwner {
        approvedOracles[_oracle] = true;
        emit OracleApproved(_oracle);
    }

    /**
     * @notice Revoke oracle approval
     * @param _oracle Oracle contract address
     */
    function revokeOracle(address _oracle) external onlyOwner {
        approvedOracles[_oracle] = false;
        emit OracleRevoked(_oracle);
    }

    /**
     * @notice Set maximum price staleness
     * @param _maxStaleness Maximum age in seconds
     */
    function setMaxPriceStaleness(uint256 _maxStaleness) external onlyOwner {
        require(_maxStaleness > 0, "Invalid staleness");
        maxPriceStaleness = _maxStaleness;
    }
}
