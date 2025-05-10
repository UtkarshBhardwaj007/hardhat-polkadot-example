// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "./openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title LendingPoolBridge
 * @dev Bridge contract that handles the lending/borrowing matching logic
 */
contract LendingPoolBridge is Ownable, ReentrancyGuard {
    struct VTLRange {
        uint256 lower;
        uint256 upper;
    }

    struct LenderOffer {
        address lender;
        uint256 amount;
        VTLRange vtlRange;
        bool isActive;
        bool proofVerified;
        uint256 wrappedTokenBalance;
    }

    struct BorrowerRequest {
        address borrower;
        uint256 collateralAmount;
        uint256 requestedAmount;
        VTLRange vtlRange;
        bool isActive;
        bool proofVerified;
        uint256 wrappedCollateralBalance;
    }

    // Mapping to track lender offers
    mapping(address => LenderOffer) public lenderOffers;
    
    // Mapping to track borrower requests
    mapping(address => BorrowerRequest) public borrowerRequests;

    // Liquidity pool for wrapped tokens
    mapping(address => uint256) public liquidityPool;

    // Oracle contract address
    address public oracle;
    
    // EVM chain contract address (LendingPool)
    address public evmContractAddress;
    
    // Wrapped token contract
    IERC20 public wrappedToken;

    event LenderOfferCreated(address indexed lender, uint256 amount, uint256 vtlLower, uint256 vtlUpper);
    event BorrowerRequestCreated(address indexed borrower, uint256 collateral, uint256 requested, uint256 vtlLower, uint256 vtlUpper);
    event MatchCreated(address indexed lender, address indexed borrower, uint256 amount);
    event CollateralRatioUpdated(address indexed borrower, uint256 ratio);
    event ProofVerified(address indexed user, bool isLender, uint256 amount);
    event WrappedTokensGenerated(address indexed user, uint256 amount);
    event LiquidationTriggered(address indexed borrower, address indexed lender, uint256 amount);

    modifier onlyOracle() {
        require(msg.sender == oracle, "Only oracle can call this");
        _;
    }

    constructor(address _oracle, address _evmContractAddress, address _wrappedToken) Ownable() {
        oracle = _oracle;
        evmContractAddress = _evmContractAddress;
        wrappedToken = IERC20(_wrappedToken);
    }

    /**
     * @dev Create a lending offer with VTL range
     * @param amount Amount willing to lend
     * @param vtlLower Lower bound of VTL range
     * @param vtlUpper Upper bound of VTL range
     */
    function createLenderOffer(uint256 amount, uint256 vtlLower, uint256 vtlUpper) external nonReentrant {
        require(vtlLower < vtlUpper, "Invalid VTL range");
        require(amount > 0, "Amount must be greater than 0");
        require(wrappedToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        
        lenderOffers[msg.sender] = LenderOffer({
            lender: msg.sender,
            amount: amount,
            vtlRange: VTLRange(vtlLower, vtlUpper),
            isActive: true,
            proofVerified: true, // Auto-verify since we have the tokens
            wrappedTokenBalance: amount
        });

        emit LenderOfferCreated(msg.sender, amount, vtlLower, vtlUpper);
    }

    /**
     * @dev Create a borrowing request with VTL range
     * @param collateralAmount Amount of collateral
     * @param requestedAmount Amount wanting to borrow
     * @param vtlLower Lower bound of VTL range
     * @param vtlUpper Upper bound of VTL range
     */
    function createBorrowerRequest(
        uint256 collateralAmount,
        uint256 requestedAmount,
        uint256 vtlLower,
        uint256 vtlUpper
    ) external nonReentrant {
        require(vtlLower < vtlUpper, "Invalid VTL range");
        require(collateralAmount > 0, "Collateral must be greater than 0");
        require(requestedAmount > 0, "Requested amount must be greater than 0");
        require(wrappedToken.transferFrom(msg.sender, address(this), collateralAmount), "Collateral transfer failed");
        
        borrowerRequests[msg.sender] = BorrowerRequest({
            borrower: msg.sender,
            collateralAmount: collateralAmount,
            requestedAmount: requestedAmount,
            vtlRange: VTLRange(vtlLower, vtlUpper),
            isActive: true,
            proofVerified: true, // Auto-verify since we have the collateral
            wrappedCollateralBalance: collateralAmount
        });

        emit BorrowerRequestCreated(msg.sender, collateralAmount, requestedAmount, vtlLower, vtlUpper);
    }

    /**
     * @dev Check if VTL ranges overlap and execute match
     * @param lender Lender address
     * @param borrower Borrower address
     */
    function executeMatch(address lender, address borrower) external nonReentrant returns (bool) {
        LenderOffer storage offer = lenderOffers[lender];
        BorrowerRequest storage request = borrowerRequests[borrower];
        
        require(offer.isActive && request.isActive, "Offers must be active");
        require(offer.proofVerified && request.proofVerified, "Proofs must be verified");
        
        if (!_doVTLRangesOverlap(offer.vtlRange, request.vtlRange)) {
            return false;
        }

        // Calculate the matched amount
        uint256 matchedAmount = _min(offer.amount, request.requestedAmount);
        
        // Update positions
        offer.amount -= matchedAmount;
        if (offer.amount == 0) {
            offer.isActive = false;
        }
        
        request.requestedAmount -= matchedAmount;
        if (request.requestedAmount == 0) {
            request.isActive = false;
        }
        
        // Transfer matched amount to borrower
        require(wrappedToken.transfer(borrower, matchedAmount), "Match transfer failed");
        
        emit MatchCreated(lender, borrower, matchedAmount);
        return true;
    }

    /**
     * @dev Trigger liquidation of a borrower's position
     * @param borrower The borrower to liquidate
     * @param lender The lender who will receive the collateral
     */
    function triggerLiquidation(address borrower, address lender) external onlyOracle {
        BorrowerRequest storage request = borrowerRequests[borrower];
        require(request.isActive && request.proofVerified, "Invalid borrower position");
        
        uint256 collateralToLiquidate = request.collateralAmount;
        
        // Transfer collateral to lender
        require(wrappedToken.transfer(lender, collateralToLiquidate), "Liquidation transfer failed");
        
        // Close the position
        request.isActive = false;
        request.collateralAmount = 0;
        
        emit LiquidationTriggered(borrower, lender, collateralToLiquidate);
    }

    /**
     * @dev Check if two VTL ranges overlap
     */
    function _doVTLRangesOverlap(VTLRange memory range1, VTLRange memory range2) internal pure returns (bool) {
        return range1.lower <= range2.upper && range2.lower <= range1.upper;
    }

    /**
     * @dev Return minimum of two numbers
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
