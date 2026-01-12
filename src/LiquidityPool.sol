// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LiquidityPool - Native ETH Vault for JuiceRoule
/// @notice Provides liquidity for the roulette game. Depositors earn/lose based on game outcomes.
/// @dev Simplified ERC4626-like vault for native ETH (not ERC20)
contract LiquidityPool is ERC20, ReentrancyGuard {
    /// @notice The roulette contract that can request funds
    address public immutable roulette;

    /// @notice Total ETH locked in pending bets (potential payouts)
    uint256 public lockedInBets;

    /// @notice Maximum percentage of pool that can be bet at once (in basis points, 100 = 1%)
    uint256 public constant MAX_BET_PERCENTAGE = 100; // 1%

    /// @notice Minimum deposit amount
    uint256 public constant MIN_DEPOSIT = 0.01 ether;

    /// @notice Events
    event Deposit(address indexed depositor, uint256 assets, uint256 shares);
    event Withdraw(address indexed withdrawer, uint256 shares, uint256 assets);
    event FundsLocked(uint256 amount);
    event FundsUnlocked(uint256 amount);
    event PayoutSent(address indexed winner, uint256 amount);
    event LossCollected(uint256 amount);

    /// @notice Errors
    error OnlyRoulette();
    error InsufficientLiquidity();
    error BelowMinDeposit();
    error ZeroShares();
    error ZeroAssets();
    error TransferFailed();

    modifier onlyRoulette() {
        if (msg.sender != roulette) revert OnlyRoulette();
        _;
    }

    /// @notice Constructor
    /// @param _roulette Address of the JuiceRoule contract
    constructor(address _roulette) ERC20("JuiceRoule LP", "jrLP") {
        roulette = _roulette;
    }

    /// @notice Deposit ETH and receive LP shares
    /// @return shares The amount of shares minted
    function deposit() external payable nonReentrant returns (uint256 shares) {
        if (msg.value < MIN_DEPOSIT) revert BelowMinDeposit();

        shares = _convertToShares(msg.value);
        if (shares == 0) revert ZeroShares();

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, msg.value, shares);
    }

    /// @notice Withdraw ETH by burning LP shares
    /// @param shares The amount of shares to burn
    /// @return assets The amount of ETH returned
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();

        assets = _convertToAssets(shares);
        if (assets == 0) revert ZeroAssets();

        // Check if there's enough unlocked liquidity
        uint256 _available = address(this).balance - lockedInBets;
        if (assets > _available) revert InsufficientLiquidity();

        _burn(msg.sender, shares);

        (bool success,) = msg.sender.call{value: assets}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, shares, assets);
    }

    /// @notice Lock funds for a pending bet (called by roulette contract)
    /// @param potentialPayout The maximum payout if the bet wins
    function lockFunds(uint256 potentialPayout) external onlyRoulette {
        uint256 _available = address(this).balance - lockedInBets;
        if (potentialPayout > _available) revert InsufficientLiquidity();

        lockedInBets += potentialPayout;
        emit FundsLocked(potentialPayout);
    }

    /// @notice Unlock funds when a bet is settled (win or lose)
    /// @param lockedAmount The amount that was locked
    function unlockFunds(uint256 lockedAmount) external onlyRoulette {
        lockedInBets -= lockedAmount;
        emit FundsUnlocked(lockedAmount);
    }

    /// @notice Send payout to winner (called by roulette contract)
    /// @param winner Address of the winner
    /// @param amount Amount to send
    function sendPayout(address winner, uint256 amount) external onlyRoulette nonReentrant {
        (bool success,) = winner.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit PayoutSent(winner, amount);
    }

    /// @notice Receive lost bet funds (called by roulette contract)
    function receiveLoss() external payable onlyRoulette {
        emit LossCollected(msg.value);
    }

    /// @notice Get the maximum bet amount based on current pool liquidity
    /// @return maxBet The maximum allowed bet
    function getMaxBet() external view returns (uint256 maxBet) {
        uint256 _available = address(this).balance - lockedInBets;
        maxBet = (_available * MAX_BET_PERCENTAGE) / 10_000;
    }

    /// @notice Get available liquidity (not locked in bets)
    /// @return available The available ETH
    function availableLiquidity() external view returns (uint256 available) {
        available = address(this).balance - lockedInBets;
    }

    /// @notice Get total assets in the pool
    /// @return total The total ETH balance
    function totalAssets() public view returns (uint256 total) {
        total = address(this).balance;
    }

    /// @notice Convert ETH amount to shares
    /// @param assets The ETH amount
    /// @return shares The equivalent shares
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        shares = _convertToShares(assets);
    }

    /// @notice Convert shares to ETH amount
    /// @param shares The share amount
    /// @return assets The equivalent ETH
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = _convertToAssets(shares);
    }

    /// @dev Internal share calculation
    function _convertToShares(uint256 assets) internal view returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            // First deposit: 1:1 ratio
            shares = assets;
        } else {
            // Proportional to existing pool
            // shares = assets * totalSupply / totalAssets
            // Note: totalAssets includes the just-deposited assets at this point
            uint256 poolBefore = address(this).balance - assets;
            if (poolBefore == 0) {
                shares = assets;
            } else {
                shares = (assets * supply) / poolBefore;
            }
        }
    }

    /// @dev Internal asset calculation
    function _convertToAssets(uint256 shares) internal view returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            assets = 0;
        } else {
            // assets = shares * totalAssets / totalSupply
            assets = (shares * address(this).balance) / supply;
        }
    }

    /// @notice Allow contract to receive ETH directly (for receiving bet losses)
    receive() external payable {}
}
