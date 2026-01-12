// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title BetTypes - Roulette bet types and validation library
/// @notice Defines all European roulette bet types and provides win checking logic
/// @dev All payouts are in format X:1 (e.g., 35 means 35:1 payout)
library BetTypes {
    /// @notice All supported bet types in European roulette
    enum BetType {
        STRAIGHT_UP, // Single number (35:1)
        SPLIT, // 2 adjacent numbers (17:1)
        STREET, // 3 numbers in a row (11:1)
        CORNER, // 4 numbers in a square (8:1)
        SIX_LINE, // 6 numbers - 2 rows (5:1)
        COLUMN, // 12 numbers - vertical column (2:1)
        DOZEN, // 12 numbers - 1-12, 13-24, 25-36 (2:1)
        RED, // 18 red numbers (1:1)
        BLACK, // 18 black numbers (1:1)
        ODD, // 18 odd numbers (1:1)
        EVEN, // 18 even numbers (1:1)
        LOW, // 1-18 (1:1)
        HIGH // 19-36 (1:1)
    }

    /// @notice Red numbers on a European roulette wheel
    /// @dev Stored as a bitmap for gas efficiency: bit N is set if N is red
    uint256 internal constant RED_NUMBERS =
        (1 << 1) |
        (1 << 3) |
        (1 << 5) |
        (1 << 7) |
        (1 << 9) |
        (1 << 12) |
        (1 << 14) |
        (1 << 16) |
        (1 << 18) |
        (1 << 19) |
        (1 << 21) |
        (1 << 23) |
        (1 << 25) |
        (1 << 27) |
        (1 << 30) |
        (1 << 32) |
        (1 << 34) |
        (1 << 36);

    /// @notice Get the payout multiplier for a bet type
    /// @param betType The type of bet
    /// @return multiplier The payout multiplier (e.g., 35 for 35:1)
    function getPayout(BetType betType) internal pure returns (uint256 multiplier) {
        if (betType == BetType.STRAIGHT_UP) return 35;
        if (betType == BetType.SPLIT) return 17;
        if (betType == BetType.STREET) return 11;
        if (betType == BetType.CORNER) return 8;
        if (betType == BetType.SIX_LINE) return 5;
        if (betType == BetType.COLUMN || betType == BetType.DOZEN) return 2;
        // All other bets (RED, BLACK, ODD, EVEN, LOW, HIGH) pay 1:1
        return 1;
    }

    /// @notice Check if a bet is a winner
    /// @param result The roulette result (0-36)
    /// @param betType The type of bet placed
    /// @param betData Additional data for the bet (number, column index, etc.)
    /// @return isWinner True if the bet wins
    function checkWin(uint8 result, BetType betType, uint256 betData) internal pure returns (bool isWinner) {
        // Zero never wins on outside bets
        if (result == 0) {
            // Only STRAIGHT_UP on 0 can win
            if (betType == BetType.STRAIGHT_UP && betData == 0) return true;
            return false;
        }

        if (betType == BetType.STRAIGHT_UP) {
            return result == uint8(betData);
        }

        if (betType == BetType.SPLIT) {
            // betData encodes two numbers: (num1 << 8) | num2
            uint8 num1 = uint8(betData >> 8);
            uint8 num2 = uint8(betData & 0xFF);
            return result == num1 || result == num2;
        }

        if (betType == BetType.STREET) {
            // betData is the first number of the street (1, 4, 7, 10, ...)
            uint8 start = uint8(betData);
            return result >= start && result < start + 3;
        }

        if (betType == BetType.CORNER) {
            // betData is top-left number of the corner
            uint8 topLeft = uint8(betData);
            return result == topLeft || result == topLeft + 1 || result == topLeft + 3 || result == topLeft + 4;
        }

        if (betType == BetType.SIX_LINE) {
            // betData is the first number of the six line
            uint8 start = uint8(betData);
            return result >= start && result < start + 6;
        }

        if (betType == BetType.COLUMN) {
            // betData is column index (0, 1, or 2)
            // Column 0: 1, 4, 7, 10, ... (result % 3 == 1)
            // Column 1: 2, 5, 8, 11, ... (result % 3 == 2)
            // Column 2: 3, 6, 9, 12, ... (result % 3 == 0)
            uint8 col = uint8(betData);
            if (col == 0) return result % 3 == 1;
            if (col == 1) return result % 3 == 2;
            return result % 3 == 0;
        }

        if (betType == BetType.DOZEN) {
            // betData is dozen index (0, 1, or 2)
            // Dozen 0: 1-12
            // Dozen 1: 13-24
            // Dozen 2: 25-36
            uint8 dozen = uint8(betData);
            if (dozen == 0) return result >= 1 && result <= 12;
            if (dozen == 1) return result >= 13 && result <= 24;
            return result >= 25 && result <= 36;
        }

        if (betType == BetType.RED) {
            return (RED_NUMBERS & (1 << result)) != 0;
        }

        if (betType == BetType.BLACK) {
            return (RED_NUMBERS & (1 << result)) == 0;
        }

        if (betType == BetType.ODD) {
            return result % 2 == 1;
        }

        if (betType == BetType.EVEN) {
            return result % 2 == 0;
        }

        if (betType == BetType.LOW) {
            return result >= 1 && result <= 18;
        }

        if (betType == BetType.HIGH) {
            return result >= 19 && result <= 36;
        }

        return false;
    }

    /// @notice Validate that bet data is valid for the given bet type
    /// @param betType The type of bet
    /// @param betData The bet data to validate
    /// @return isValid True if the bet data is valid
    function validateBetData(BetType betType, uint256 betData) internal pure returns (bool isValid) {
        if (betType == BetType.STRAIGHT_UP) {
            return betData <= 36;
        }

        if (betType == BetType.SPLIT) {
            uint8 num1 = uint8(betData >> 8);
            uint8 num2 = uint8(betData & 0xFF);
            if (num1 > 36 || num2 > 36 || num1 >= num2) return false;
            // Check adjacency (horizontal or vertical)
            int8 diff = int8(num2) - int8(num1);
            return diff == 1 || diff == 3;
        }

        if (betType == BetType.STREET) {
            // Valid streets start at 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34
            uint8 start = uint8(betData);
            return start >= 1 && start <= 34 && (start - 1) % 3 == 0;
        }

        if (betType == BetType.CORNER) {
            // Valid corners: top-left can be 1,2,4,5,7,8,10,11,13,14,16,17,19,20,22,23,25,26,28,29,31,32
            uint8 topLeft = uint8(betData);
            if (topLeft < 1 || topLeft > 32) return false;
            // Cannot be in column 3 (3, 6, 9, ...)
            if (topLeft % 3 == 0) return false;
            return true;
        }

        if (betType == BetType.SIX_LINE) {
            // Valid six lines start at 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31
            uint8 start = uint8(betData);
            return start >= 1 && start <= 31 && (start - 1) % 3 == 0;
        }

        if (betType == BetType.COLUMN || betType == BetType.DOZEN) {
            return betData <= 2;
        }

        // RED, BLACK, ODD, EVEN, LOW, HIGH don't need betData validation
        return true;
    }
}
