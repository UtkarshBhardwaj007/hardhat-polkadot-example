// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniswapLimitOrderAdapter
 * @notice Adapter for executing limit order swaps on Uniswap V2-compatible DEXes
 * @dev Works with StellaSwap, BeamSwap, and other Uniswap V2 forks on Moonbeam/PassetHub
 */
contract UniswapLimitOrderAdapter is Ownable {

    // ============ Interfaces ============

    /**
     * @notice Uniswap V2 Router interface
     */
    interface IUniswapV2Router {
        function swapExactTokensForTokens(
            uint256 amountIn,
            uint256 amountOutMin,
            address[] calldata path,
            address to,
            uint256 deadline
        ) external returns (uint256[] memory amounts);

        function swapTokensForExactTokens(
            uint256 amountOut,
            uint256 amountInMax,
            address[] calldata path,
            address to,
            uint256 deadline
        ) external returns (uint256[] memory amounts);

        function getAmountsOut(
            uint256 amountIn,
            address[] calldata path
        ) external view returns (uint256[] memory amounts);
    }

    // ============ State Variables ============

    /// @notice Action router that can call this adapter
    address public actionRouter;

    /// @notice Default deadline extension (5 minutes)
    uint256 public constant DEADLINE_EXTENSION = 5 minutes;

    /// @notice Supported DEX routers on Moonbeam
    mapping(address => bool) public supportedRouters;

    // ============ Events ============

    event SwapExecuted(
        uint256 indexed taskId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event RouterAdded(address indexed router);
    event RouterRemoved(address indexed router);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Core Functions ============

    /**
     * @notice Execute a limit order swap
     * @param _taskId Task identifier
     * @param _protocol DEX router address
     * @param _selector Function selector (not used, for interface compatibility)
     * @param _params Encoded swap parameters
     * @param _value ETH value (not used for token swaps)
     * @return success Whether swap succeeded
     */
    function execute(
        uint256 _taskId,
        address _protocol,
        bytes4 _selector,
        bytes calldata _params,
        uint256 _value
    ) external returns (bool success) {
        require(msg.sender == actionRouter, "Only action router");
        require(supportedRouters[_protocol], "Router not supported");

        // Decode swap parameters
        (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin,
            address recipient,
            address creator  // Task creator who owns the tokens
        ) = abi.decode(_params, (address, address, uint256, uint256, address, address));

        // Validate parameters
        require(tokenIn != address(0), "Invalid tokenIn");
        require(tokenOut != address(0), "Invalid tokenOut");
        require(amountIn > 0, "Invalid amountIn");
        require(amountOutMin > 0, "Invalid amountOutMin");
        require(recipient != address(0), "Invalid recipient");
        require(creator != address(0), "Invalid creator");

        // Check current price meets condition
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amountsOut = IUniswapV2Router(_protocol).getAmountsOut(
            amountIn,
            path
        );

        // Verify we can get at least amountOutMin
        if (amountsOut[1] < amountOutMin) {
            return false; // Price condition not met
        }

        // Transfer tokens from task creator to this adapter
        bool transferSuccess = IERC20(tokenIn).transferFrom(
            creator,
            address(this),
            amountIn
        );

        if (!transferSuccess) {
            return false; // Token transfer failed
        }

        // Approve router to spend tokens
        IERC20(tokenIn).approve(_protocol, amountIn);

        // Execute swap
        try IUniswapV2Router(_protocol).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            block.timestamp + DEADLINE_EXTENSION
        ) returns (uint256[] memory amounts) {
            emit SwapExecuted(
                _taskId,
                tokenIn,
                tokenOut,
                amounts[0],
                amounts[1]
            );
            return true;
        } catch {
            // Swap failed - return tokens to creator
            IERC20(tokenIn).transfer(creator, amountIn);
            return false;
        }
    }

    /**
     * @notice Preview swap output without executing
     * @param _router DEX router address
     * @param _tokenIn Input token
     * @param _tokenOut Output token
     * @param _amountIn Input amount
     * @return amountOut Expected output amount
     */
    function previewSwap(
        address _router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut) {
        require(supportedRouters[_router], "Router not supported");

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        uint256[] memory amounts = IUniswapV2Router(_router).getAmountsOut(
            _amountIn,
            path
        );

        return amounts[1];
    }

    /**
     * @notice Check if limit order condition is met
     * @param _router DEX router address
     * @param _tokenIn Input token
     * @param _tokenOut Output token
     * @param _amountIn Input amount
     * @param _minAmountOut Minimum acceptable output
     * @return bool Whether condition is met
     */
    function checkLimitOrderCondition(
        address _router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external view returns (bool) {
        if (!supportedRouters[_router]) {
            return false;
        }

        try this.previewSwap(_router, _tokenIn, _tokenOut, _amountIn) returns (uint256 amountOut) {
            return amountOut >= _minAmountOut;
        } catch {
            return false;
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Set action router address
     * @param _actionRouter Action router contract
     */
    function setActionRouter(address _actionRouter) external onlyOwner {
        require(_actionRouter != address(0), "Invalid router");
        actionRouter = _actionRouter;
    }

    /**
     * @notice Add supported DEX router
     * @param _router Router address
     */
    function addRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        supportedRouters[_router] = true;
        emit RouterAdded(_router);
    }

    /**
     * @notice Remove DEX router
     * @param _router Router address
     */
    function removeRouter(address _router) external onlyOwner {
        supportedRouters[_router] = false;
        emit RouterRemoved(_router);
    }

    /**
     * @notice Batch add multiple routers
     * @param _routers Array of router addresses
     */
    function batchAddRouters(address[] calldata _routers) external onlyOwner {
        for (uint256 i = 0; i < _routers.length; i++) {
            supportedRouters[_routers[i]] = true;
            emit RouterAdded(_routers[i]);
        }
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param _token Token address
     * @param _to Recipient
     * @param _amount Amount
     */
    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Invalid recipient");
        IERC20(_token).transfer(_to, _amount);
    }
}
