// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {BetTypes} from "../src/libraries/BetTypes.sol";

contract VerifySplitFix is Test {
    
    function test_Split_ValidVertical() public pure {
        // 1-2, 2-3, 4-5, 5-6 should be valid (same street)
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(1) << 8) | 2), "1-2 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(2) << 8) | 3), "2-3 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(4) << 8) | 5), "4-5 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(5) << 8) | 6), "5-6 valid");
    }
    
    function test_Split_ValidHorizontal() public pure {
        // 1-4, 2-5, 3-6 should be valid (same column, diff=3)
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(1) << 8) | 4), "1-4 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(2) << 8) | 5), "2-5 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(3) << 8) | 6), "3-6 valid");
    }
    
    function test_Split_InvalidCrossStreet() public pure {
        // 3-4, 6-7, 9-10 should be INVALID (different streets!)
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(3) << 8) | 4), "3-4 invalid");
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(6) << 8) | 7), "6-7 invalid");
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(9) << 8) | 10), "9-10 invalid");
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(12) << 8) | 13), "12-13 invalid");
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(33) << 8) | 34), "33-34 invalid");
    }
    
    function test_Split_ZeroSplits() public pure {
        // 0-1, 0-2, 0-3 are valid, 0-4 is not
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(0) << 8) | 1), "0-1 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(0) << 8) | 2), "0-2 valid");
        assertTrue(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(0) << 8) | 3), "0-3 valid");
        assertFalse(BetTypes.validateBetData(BetTypes.BetType.SPLIT, (uint256(0) << 8) | 4), "0-4 invalid");
    }
    
    function test_Split_All11CrossStreetPairsRejected() public pure {
        // All 11 cross-street pairs should be rejected
        uint256 rejectedCount = 0;
        for (uint8 i = 3; i <= 33; i += 3) {
            uint256 betData = (uint256(i) << 8) | uint256(i + 1);
            if (!BetTypes.validateBetData(BetTypes.BetType.SPLIT, betData)) {
                rejectedCount++;
            }
        }
        assertEq(rejectedCount, 11, "All 11 invalid pairs rejected");
    }
}
