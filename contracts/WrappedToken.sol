// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedToken - A token for wrapping assets on Westend Asset Hub
/// @custom:substrate-pallet contracts
contract WrappedToken is ERC20, Ownable {
    constructor() ERC20("Wrapped Asset", "WASSET") {}

    /// @notice Mint new tokens
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

    /// @notice Transfer tokens with a custom selector for Substrate compatibility
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return success True if the transfer was successful
    function transfer_tokens(address to, uint256 amount) public returns (bool success) {
        transfer(to, amount);
        return true;
    }
}
