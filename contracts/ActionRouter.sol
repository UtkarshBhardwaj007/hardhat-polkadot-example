// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ActionRouter
 * @notice Routes task actions to protocol adapters or direct protocol calls
 * @dev Central hub for executing arbitrary protocol interactions with safety checks
 */
contract ActionRouter is Ownable, ReentrancyGuard {

    // ============ State Variables ============

    /// @notice Mapping from protocol address to its adapter (if exists)
    mapping(address => address) public protocolAdapters;

    /// @notice Approved protocols that can be called directly
    mapping(address => bool) public approvedProtocols;

    /// @notice Task registry that can call this router
    address public taskRegistry;

    /// @notice Maximum gas allowed per action
    uint256 public maxGasPerAction = 500000;

    /// @notice Enable/disable direct protocol calls (without adapter)
    bool public allowDirectCalls = true;

    // ============ Events ============

    event ActionExecuted(
        uint256 indexed taskId,
        address indexed protocol,
        bytes4 selector,
        bool success
    );

    event AdapterRegistered(
        address indexed protocol,
        address indexed adapter
    );

    event AdapterRemoved(address indexed protocol);

    event ProtocolApproved(address indexed protocol);
    event ProtocolRevoked(address indexed protocol);

    // ============ Modifiers ============

    modifier onlyTaskRegistry() {
        require(msg.sender == taskRegistry, "Only task registry");
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Core Functions ============

    /**
     * @notice Route an action to the appropriate executor
     * @param _taskId Task ID for tracking
     * @param _protocol Protocol address to interact with
     * @param _selector Function selector to call
     * @param _params ABI-encoded function parameters
     * @param _value ETH value to send
     * @return success Whether action executed successfully
     */
    function routeAction(
        uint256 _taskId,
        address _protocol,
        bytes4 _selector,
        bytes calldata _params,
        uint256 _value
    ) external onlyTaskRegistry nonReentrant returns (bool success) {

        require(_protocol != address(0), "Invalid protocol");
        require(approvedProtocols[_protocol], "Protocol not approved");

        // Check if we have a custom adapter for this protocol
        address adapter = protocolAdapters[_protocol];

        if (adapter != address(0)) {
            // Use adapter for safer interaction
            success = _executeViaAdapter(
                adapter,
                _taskId,
                _protocol,
                _selector,
                _params,
                _value
            );
        } else if (allowDirectCalls) {
            // Direct protocol call
            success = _executeDirectCall(
                _protocol,
                _selector,
                _params,
                _value
            );
        } else {
            revert("No adapter and direct calls disabled");
        }

        emit ActionExecuted(_taskId, _protocol, _selector, success);
        return success;
    }

    /**
     * @notice Execute action via protocol adapter
     * @param _adapter Adapter contract address
     * @param _taskId Task ID
     * @param _protocol Protocol address
     * @param _selector Function selector
     * @param _params Parameters
     * @param _value ETH value
     * @return success Whether execution succeeded
     */
    function _executeViaAdapter(
        address _adapter,
        uint256 _taskId,
        address _protocol,
        bytes4 _selector,
        bytes calldata _params,
        uint256 _value
    ) internal returns (bool success) {

        // Call adapter's execute function
        (bool callSuccess, bytes memory returnData) = _adapter.call{
            gas: maxGasPerAction,
            value: _value
        }(
            abi.encodeWithSignature(
                "execute(uint256,address,bytes4,bytes,uint256)",
                _taskId,
                _protocol,
                _selector,
                _params,
                _value
            )
        );

        if (callSuccess) {
            // Adapter returns bool indicating success
            success = abi.decode(returnData, (bool));
        } else {
            success = false;
        }
    }

    /**
     * @notice Execute direct call to protocol
     * @param _protocol Protocol address
     * @param _selector Function selector
     * @param _params Parameters
     * @param _value ETH value
     * @return success Whether call succeeded
     */
    function _executeDirectCall(
        address _protocol,
        bytes4 _selector,
        bytes calldata _params,
        uint256 _value
    ) internal returns (bool success) {

        // Construct full calldata
        bytes memory callData = abi.encodePacked(_selector, _params);

        // Execute call with gas limit
        (bool callSuccess, ) = _protocol.call{
            gas: maxGasPerAction,
            value: _value
        }(callData);

        return callSuccess;
    }

    // ============ Admin Functions ============

    /**
     * @notice Register a protocol adapter
     * @param _protocol Protocol address
     * @param _adapter Adapter contract that handles this protocol
     */
    function registerAdapter(
        address _protocol,
        address _adapter
    ) external onlyOwner {
        require(_protocol != address(0), "Invalid protocol");
        require(_adapter != address(0), "Invalid adapter");

        protocolAdapters[_protocol] = _adapter;
        emit AdapterRegistered(_protocol, _adapter);
    }

    /**
     * @notice Batch register multiple adapters
     * @param _protocols Array of protocol addresses
     * @param _adapters Array of adapter addresses
     */
    function batchRegisterAdapters(
        address[] calldata _protocols,
        address[] calldata _adapters
    ) external onlyOwner {
        require(_protocols.length == _adapters.length, "Length mismatch");

        for (uint256 i = 0; i < _protocols.length; i++) {
            protocolAdapters[_protocols[i]] = _adapters[i];
            emit AdapterRegistered(_protocols[i], _adapters[i]);
        }
    }

    /**
     * @notice Remove adapter for a protocol (fall back to direct calls)
     * @param _protocol Protocol address
     */
    function removeAdapter(address _protocol) external onlyOwner {
        delete protocolAdapters[_protocol];
        emit AdapterRemoved(_protocol);
    }

    /**
     * @notice Approve a protocol for interactions
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
     * @notice Set task registry address
     * @param _taskRegistry Task registry that can call this router
     */
    function setTaskRegistry(address _taskRegistry) external onlyOwner {
        require(_taskRegistry != address(0), "Invalid registry");
        taskRegistry = _taskRegistry;
    }

    /**
     * @notice Set maximum gas per action
     * @param _maxGas Maximum gas limit
     */
    function setMaxGasPerAction(uint256 _maxGas) external onlyOwner {
        require(_maxGas > 0 && _maxGas <= 5000000, "Invalid gas limit");
        maxGasPerAction = _maxGas;
    }

    /**
     * @notice Enable/disable direct protocol calls
     * @param _allowed Whether to allow direct calls
     */
    function setAllowDirectCalls(bool _allowed) external onlyOwner {
        allowDirectCalls = _allowed;
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param _token Token address (address(0) for native)
     * @param _to Recipient address
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Invalid recipient");

        if (_token == address(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(_token).transfer(_to, _amount);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check if protocol has an adapter
     * @param _protocol Protocol address
     * @return bool Whether adapter exists
     */
    function hasAdapter(address _protocol) external view returns (bool) {
        return protocolAdapters[_protocol] != address(0);
    }

    /**
     * @notice Get adapter for protocol
     * @param _protocol Protocol address
     * @return address Adapter address (0 if none)
     */
    function getAdapter(address _protocol) external view returns (address) {
        return protocolAdapters[_protocol];
    }

    // Allow receiving ETH
    receive() external payable {}
}
