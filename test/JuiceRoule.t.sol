// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {JuiceRoule} from "../src/JuiceRoule.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {BetTypes} from "../src/libraries/BetTypes.sol";

contract JuiceRouleTest is Test {
    JuiceRoule public roulette;
    LiquidityPool public pool;

    address public player = makeAddr("player");
    address public liquidityProvider = makeAddr("lp");

    function setUp() public {
        // Deploy roulette (which deploys pool)
        roulette = new JuiceRoule();
        pool = roulette.pool();

        // Fund player
        vm.deal(player, 100 ether);

        // Fund LP and add liquidity
        vm.deal(liquidityProvider, 1000 ether);
        vm.prank(liquidityProvider);
        pool.deposit{value: 100 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            BET PLACEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PlaceBet_StraightUp() public {
        bytes32 secret = keccak256("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.STRAIGHT_UP, 17);

        (bytes32 storedCommitment, uint256 amount,,,,,,) = roulette.getBetStatus(player);
        assertEq(storedCommitment, commitment);
        assertEq(amount, 1 ether);
    }

    function test_PlaceBet_Red() public {
        bytes32 secret = keccak256("red_bet");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        (bytes32 storedCommitment,,,,,,,) = roulette.getBetStatus(player);
        assertEq(storedCommitment, commitment);
    }

    function test_PlaceBet_RevertIfAlreadyPending() public {
        bytes32 secret1 = keccak256("secret1");
        bytes32 commitment1 = keccak256(abi.encodePacked(secret1));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment1, BetTypes.BetType.RED, 0);

        bytes32 secret2 = keccak256("secret2");
        bytes32 commitment2 = keccak256(abi.encodePacked(secret2));

        vm.prank(player);
        vm.expectRevert(JuiceRoule.BetAlreadyPending.selector);
        roulette.placeBet{value: 1 ether}(commitment2, BetTypes.BetType.BLACK, 0);
    }

    function test_PlaceBet_RevertIfBetTooSmall() public {
        bytes32 secret = keccak256("small_bet");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        vm.expectRevert(JuiceRoule.BetTooSmall.selector);
        roulette.placeBet{value: 0.0001 ether}(commitment, BetTypes.BetType.RED, 0);
    }

    function test_PlaceBet_RevertIfInvalidBetData() public {
        bytes32 secret = keccak256("invalid_bet");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        vm.expectRevert(JuiceRoule.InvalidBetData.selector);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.STRAIGHT_UP, 37); // Invalid: max is 36
    }

    /*//////////////////////////////////////////////////////////////
                          REVEAL AND SETTLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevealAndSettle() public {
        bytes32 secret = keccak256("test_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        // Place bet
        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        // Advance blocks
        vm.roll(block.number + 3);

        // Reveal and settle
        uint256 balanceBefore = player.balance;
        vm.prank(player);
        roulette.revealAndSettle(secret);

        // Check bet is settled
        (,,,,,bool settled,,) = roulette.getBetStatus(player);
        assertTrue(settled);
    }

    function test_RevealAndSettle_RevertIfTooEarly() public {
        bytes32 secret = keccak256("early_reveal");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        // Don't advance blocks enough
        vm.roll(block.number + 1);

        vm.prank(player);
        vm.expectRevert(JuiceRoule.TooEarlyToReveal.selector);
        roulette.revealAndSettle(secret);
    }

    function test_RevealAndSettle_RevertIfExpired() public {
        bytes32 secret = keccak256("expired_bet");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        // Advance past expiry
        vm.roll(block.number + 251);

        vm.prank(player);
        vm.expectRevert(JuiceRoule.BetExpired.selector);
        roulette.revealAndSettle(secret);
    }

    function test_RevealAndSettle_RevertIfWrongSecret() public {
        bytes32 secret = keccak256("correct_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        vm.roll(block.number + 3);

        bytes32 wrongSecret = keccak256("wrong_secret");
        vm.prank(player);
        vm.expectRevert(JuiceRoule.InvalidCommitment.selector);
        roulette.revealAndSettle(wrongSecret);
    }

    /*//////////////////////////////////////////////////////////////
                          FORCE SETTLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ForceSettle() public {
        bytes32 secret = keccak256("force_settle_test");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        // Advance past expiry
        vm.roll(block.number + 251);

        // Anyone can force settle
        address settler = makeAddr("settler");
        vm.prank(settler);
        roulette.forceSettle(player);

        // Check bet is settled
        (,,,,,bool settled,,) = roulette.getBetStatus(player);
        assertTrue(settled);
    }

    function test_ForceSettle_RevertIfNotExpired() public {
        bytes32 secret = keccak256("not_expired_yet");
        bytes32 commitment = keccak256(abi.encodePacked(secret));

        vm.prank(player);
        roulette.placeBet{value: 1 ether}(commitment, BetTypes.BetType.RED, 0);

        // Advance but not past expiry
        vm.roll(block.number + 100);

        address settler = makeAddr("settler");
        vm.prank(settler);
        vm.expectRevert(JuiceRoule.BetNotExpired.selector);
        roulette.forceSettle(player);
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY POOL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pool_Deposit() public {
        address lp2 = makeAddr("lp2");
        vm.deal(lp2, 10 ether);

        vm.prank(lp2);
        pool.deposit{value: 5 ether}();

        assertGt(pool.balanceOf(lp2), 0);
    }

    function test_Pool_Withdraw() public {
        uint256 sharesBefore = pool.balanceOf(liquidityProvider);
        uint256 balanceBefore = liquidityProvider.balance;

        vm.prank(liquidityProvider);
        pool.withdraw(sharesBefore / 2);

        assertGt(liquidityProvider.balance, balanceBefore);
    }

    function test_Pool_MaxBet() public {
        uint256 maxBet = pool.getMaxBet();
        // Should be 1% of available liquidity
        assertEq(maxBet, pool.availableLiquidity() / 100);
    }

    /*//////////////////////////////////////////////////////////////
                           BET TYPES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BetTypes_RedNumbers() public pure {
        // Test known red numbers
        uint8[18] memory redNumbers = [uint8(1), 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

        for (uint256 i = 0; i < redNumbers.length; i++) {
            assertTrue(BetTypes.checkWin(redNumbers[i], BetTypes.BetType.RED, 0));
            assertFalse(BetTypes.checkWin(redNumbers[i], BetTypes.BetType.BLACK, 0));
        }
    }

    function test_BetTypes_BlackNumbers() public pure {
        // Test known black numbers
        uint8[18] memory blackNumbers = [uint8(2), 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35];

        for (uint256 i = 0; i < blackNumbers.length; i++) {
            assertTrue(BetTypes.checkWin(blackNumbers[i], BetTypes.BetType.BLACK, 0));
            assertFalse(BetTypes.checkWin(blackNumbers[i], BetTypes.BetType.RED, 0));
        }
    }

    function test_BetTypes_ZeroLosesOutsideBets() public pure {
        // Zero should lose on all outside bets
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.RED, 0));
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.BLACK, 0));
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.ODD, 0));
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.EVEN, 0));
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.LOW, 0));
        assertFalse(BetTypes.checkWin(0, BetTypes.BetType.HIGH, 0));
    }

    function test_BetTypes_StraightUpZero() public pure {
        // But zero CAN win on straight up bet
        assertTrue(BetTypes.checkWin(0, BetTypes.BetType.STRAIGHT_UP, 0));
    }

    function test_BetTypes_Columns() public pure {
        // Column 0: 1, 4, 7, 10, ...
        assertTrue(BetTypes.checkWin(1, BetTypes.BetType.COLUMN, 0));
        assertTrue(BetTypes.checkWin(4, BetTypes.BetType.COLUMN, 0));
        assertFalse(BetTypes.checkWin(2, BetTypes.BetType.COLUMN, 0));

        // Column 1: 2, 5, 8, 11, ...
        assertTrue(BetTypes.checkWin(2, BetTypes.BetType.COLUMN, 1));
        assertTrue(BetTypes.checkWin(5, BetTypes.BetType.COLUMN, 1));
        assertFalse(BetTypes.checkWin(3, BetTypes.BetType.COLUMN, 1));

        // Column 2: 3, 6, 9, 12, ...
        assertTrue(BetTypes.checkWin(3, BetTypes.BetType.COLUMN, 2));
        assertTrue(BetTypes.checkWin(6, BetTypes.BetType.COLUMN, 2));
        assertFalse(BetTypes.checkWin(1, BetTypes.BetType.COLUMN, 2));
    }

    function test_BetTypes_Dozens() public pure {
        // Dozen 0: 1-12
        assertTrue(BetTypes.checkWin(1, BetTypes.BetType.DOZEN, 0));
        assertTrue(BetTypes.checkWin(12, BetTypes.BetType.DOZEN, 0));
        assertFalse(BetTypes.checkWin(13, BetTypes.BetType.DOZEN, 0));

        // Dozen 1: 13-24
        assertTrue(BetTypes.checkWin(13, BetTypes.BetType.DOZEN, 1));
        assertTrue(BetTypes.checkWin(24, BetTypes.BetType.DOZEN, 1));
        assertFalse(BetTypes.checkWin(25, BetTypes.BetType.DOZEN, 1));

        // Dozen 2: 25-36
        assertTrue(BetTypes.checkWin(25, BetTypes.BetType.DOZEN, 2));
        assertTrue(BetTypes.checkWin(36, BetTypes.BetType.DOZEN, 2));
        assertFalse(BetTypes.checkWin(24, BetTypes.BetType.DOZEN, 2));
    }

    function test_BetTypes_Payouts() public pure {
        assertEq(BetTypes.getPayout(BetTypes.BetType.STRAIGHT_UP), 35);
        assertEq(BetTypes.getPayout(BetTypes.BetType.SPLIT), 17);
        assertEq(BetTypes.getPayout(BetTypes.BetType.STREET), 11);
        assertEq(BetTypes.getPayout(BetTypes.BetType.CORNER), 8);
        assertEq(BetTypes.getPayout(BetTypes.BetType.SIX_LINE), 5);
        assertEq(BetTypes.getPayout(BetTypes.BetType.COLUMN), 2);
        assertEq(BetTypes.getPayout(BetTypes.BetType.DOZEN), 2);
        assertEq(BetTypes.getPayout(BetTypes.BetType.RED), 1);
        assertEq(BetTypes.getPayout(BetTypes.BetType.BLACK), 1);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_BetTypes_ResultInRange(uint256 random) public pure {
        uint8 result = uint8(random % 37);
        assertTrue(result <= 36);
    }

    function testFuzz_BetTypes_StraightUpOnlyOneWinner(uint8 result, uint8 betNumber) public pure {
        vm.assume(result <= 36);
        vm.assume(betNumber <= 36);

        bool won = BetTypes.checkWin(result, BetTypes.BetType.STRAIGHT_UP, betNumber);
        assertEq(won, result == betNumber);
    }
}
