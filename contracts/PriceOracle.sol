// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @dev Oracle contract for monitoring asset prices and collateral ratios
 */
contract PriceOracle is Ownable {
    struct AssetPrice {
        uint256 price;
        uint256 lastUpdate;
        bool active;
    }

    // Mapping of asset address to its price data
    mapping(address => AssetPrice) public assetPrices;
    
    // Minimum time between updates
    uint256 public constant MIN_UPDATE_INTERVAL = 1 hours;
    
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event CollateralRatioUpdated(address indexed borrower, uint256 ratio);

    constructor() Ownable() {}

    /**
     * @dev Update price for an asset
     * @param asset The asset address
     * @param price The new price (scaled by 1e18)
     */
    function updateAssetPrice(address asset, uint256 price) external onlyOwner {
        require(price > 0, "Price must be greater than 0");
        
        AssetPrice storage assetPrice = assetPrices[asset];
        require(
            block.timestamp >= assetPrice.lastUpdate + MIN_UPDATE_INTERVAL,
            "Too soon to update"
        );
        
        assetPrice.price = price;
        assetPrice.lastUpdate = block.timestamp;
        assetPrice.active = true;
        
        emit PriceUpdated(asset, price, block.timestamp);
    }

    /**
     * @dev Calculate collateral ratio for a borrower
     * @param borrower The borrower's address
     * @param collateralAsset The collateral asset address
     * @param borrowedAsset The borrowed asset address
     * @param collateralAmount The amount of collateral
     * @param borrowedAmount The amount borrowed
     * @return ratio The collateral ratio (scaled by 100)
     */
    function calculateCollateralRatio(
        address borrower,
        address collateralAsset,
        address borrowedAsset,
        uint256 collateralAmount,
        uint256 borrowedAmount
    ) external view returns (uint256 ratio) {
        require(borrowedAmount > 0, "Borrowed amount must be greater than 0");
        
        AssetPrice storage collateralPrice = assetPrices[collateralAsset];
        AssetPrice storage borrowedPrice = assetPrices[borrowedAsset];
        
        require(collateralPrice.active && borrowedPrice.active, "Prices not active");
        
        uint256 collateralValue = (collateralAmount * collateralPrice.price) / 1e18;
        uint256 borrowedValue = (borrowedAmount * borrowedPrice.price) / 1e18;
        
        // Calculate ratio (scaled by 100 for precision)
        ratio = (collateralValue * 100) / borrowedValue;
        
        return ratio;
    }

    /**
     * @dev Get latest price for an asset
     * @param asset The asset address
     * @return price The latest price
     */
    function getLatestPrice(address asset) external view returns (uint256 price) {
        AssetPrice storage assetPrice = assetPrices[asset];
        require(assetPrice.active, "Price not active");
        return assetPrice.price;
    }

    /**
     * @dev Check if an asset price is active and recent
     * @param asset The asset address
     * @return bool True if price is active and recent
     */
    function isPriceActive(address asset) external view returns (bool) {
        AssetPrice storage assetPrice = assetPrices[asset];
        return assetPrice.active && 
               block.timestamp < assetPrice.lastUpdate + MIN_UPDATE_INTERVAL;
    }
}
