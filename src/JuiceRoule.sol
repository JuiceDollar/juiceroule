// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BetTypes} from "./libraries/BetTypes.sol";
import {LiquidityPool} from "./LiquidityPool.sol";

/// @title JuiceRoule - Decentralized On-Chain Roulette
/// @notice Fully decentralized European roulette using commit-reveal + future blockhash
/// @dev No oracle, no operator - pure smart contract randomness
contract JuiceRoule is ReentrancyGuard {
    using BetTypes for BetTypes.BetType;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Bet {
        bytes32 commitment; // keccak256(secret)
        uint256 amount; // Bet amount in wei
        BetTypes.BetType betType; // Type of bet
        uint256 betData; // Bet-specific data (number, column, etc.)
        uint256 commitBlock; // Block number when bet was placed
        uint256 potentialPayout; // Amount locked in pool
        bool settled; // Whether bet has been resolved
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The liquidity pool contract
    LiquidityPool public immutable pool;

    /// @notice Pending bets by player address
    mapping(address => Bet) public bets;

    /// @notice Minimum blocks to wait before reveal (prevents same-block manipulation)
    uint256 public constant MIN_REVEAL_DELAY = 2;

    /// @notice Maximum blocks before bet expires (blockhash only available for 256 blocks)
    uint256 public constant MAX_REVEAL_DELAY = 250;

    /// @notice Minimum bet amount
    uint256 public constant MIN_BET = 0.001 ether;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BetPlaced(
        address indexed player,
        bytes32 commitment,
        BetTypes.BetType betType,
        uint256 betData,
        uint256 amount,
        uint256 commitBlock
    );

    event BetSettled(
        address indexed player, uint8 result, bool won, uint256 payout, bytes32 commitment, bytes32 secret
    );

    event BetForceSettled(address indexed player, address indexed settler, bytes32 commitment);

    event BetCancelled(address indexed player, bytes32 commitment);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error BetAlreadyPending();
    error NoPendingBet();
    error BetAlreadySettled();
    error InvalidCommitment();
    error TooEarlyToReveal();
    error BetExpired();
    error BetNotExpired();
    error InvalidBetType();
    error InvalidBetData();
    error BetTooSmall();
    error BetTooLarge();
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy JuiceRoule with a new liquidity pool
    constructor() {
        pool = new LiquidityPool(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                              BETTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Place a bet with a commitment
    /// @param commitment The keccak256 hash of the player's secret
    /// @param betType The type of bet to place
    /// @param betData Additional data for the bet (depends on bet type)
    function placeBet(bytes32 commitment, BetTypes.BetType betType, uint256 betData) external payable nonReentrant {
        // Validate no pending bet
        if (bets[msg.sender].commitment != bytes32(0) && !bets[msg.sender].settled) {
            revert BetAlreadyPending();
        }

        // Validate commitment
        if (commitment == bytes32(0)) revert InvalidCommitment();

        // Validate bet amount
        if (msg.value < MIN_BET) revert BetTooSmall();

        uint256 maxBet = pool.getMaxBet();
        if (msg.value > maxBet) revert BetTooLarge();

        // Validate bet type and data
        if (uint8(betType) > uint8(BetTypes.BetType.HIGH)) revert InvalidBetType();
        if (!BetTypes.validateBetData(betType, betData)) revert InvalidBetData();

        // Calculate potential payout
        uint256 multiplier = BetTypes.getPayout(betType);
        uint256 potentialPayout = msg.value + (msg.value * multiplier);

        // Lock funds in pool
        pool.lockFunds(potentialPayout);

        // Store bet
        bets[msg.sender] = Bet({
            commitment: commitment,
            amount: msg.value,
            betType: betType,
            betData: betData,
            commitBlock: block.number,
            potentialPayout: potentialPayout,
            settled: false
        });

        emit BetPlaced(msg.sender, commitment, betType, betData, msg.value, block.number);
    }

    /// @notice Reveal secret and settle bet
    /// @param secret The original secret that was hashed for the commitment
    function revealAndSettle(bytes32 secret) external nonReentrant {
        Bet storage bet = bets[msg.sender];

        // Validate bet exists and not settled
        if (bet.commitment == bytes32(0)) revert NoPendingBet();
        if (bet.settled) revert BetAlreadySettled();

        // Validate timing
        if (block.number < bet.commitBlock + MIN_REVEAL_DELAY) revert TooEarlyToReveal();
        if (block.number > bet.commitBlock + MAX_REVEAL_DELAY) revert BetExpired();

        // Validate commitment
        if (keccak256(abi.encodePacked(secret)) != bet.commitment) {
            revert InvalidCommitment();
        }

        // Generate random number using secret + future blockhash
        bytes32 blockHash = blockhash(bet.commitBlock + 1);
        uint256 random = uint256(keccak256(abi.encodePacked(secret, blockHash)));
        uint8 result = uint8(random % 37); // 0-36 for European roulette

        // Check if bet won
        bool won = BetTypes.checkWin(result, bet.betType, bet.betData);

        // Mark as settled
        bet.settled = true;

        // Unlock funds from pool
        pool.unlockFunds(bet.potentialPayout);

        uint256 payout = 0;
        if (won) {
            // Calculate payout: original bet + winnings
            uint256 multiplier = BetTypes.getPayout(bet.betType);
            payout = bet.amount + (bet.amount * multiplier);

            // Send payout from pool
            pool.sendPayout(msg.sender, payout);
        } else {
            // Send bet amount to pool as profit
            pool.receiveLoss{value: bet.amount}();
        }

        emit BetSettled(msg.sender, result, won, payout, bet.commitment, secret);
    }

    /// @notice Force settle an expired bet (player loses)
    /// @param player Address of the player with expired bet
    function forceSettle(address player) external nonReentrant {
        Bet storage bet = bets[player];

        // Validate bet exists and not settled
        if (bet.commitment == bytes32(0)) revert NoPendingBet();
        if (bet.settled) revert BetAlreadySettled();

        // Must be expired
        if (block.number <= bet.commitBlock + MAX_REVEAL_DELAY) revert BetNotExpired();

        // Mark as settled
        bet.settled = true;

        // Unlock funds from pool
        pool.unlockFunds(bet.potentialPayout);

        // Player loses - send bet amount to pool
        pool.receiveLoss{value: bet.amount}();

        emit BetForceSettled(player, msg.sender, bet.commitment);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get player's current bet status
    /// @param player The player address
    /// @return commitment The bet commitment
    /// @return amount The bet amount
    /// @return betType The bet type
    /// @return betData The bet data
    /// @return commitBlock The block when bet was placed
    /// @return settled Whether bet is settled
    /// @return canReveal Whether bet can be revealed now
    /// @return isExpired Whether bet has expired
    function getBetStatus(address player)
        external
        view
        returns (
            bytes32 commitment,
            uint256 amount,
            BetTypes.BetType betType,
            uint256 betData,
            uint256 commitBlock,
            bool settled,
            bool canReveal,
            bool isExpired
        )
    {
        Bet storage bet = bets[player];
        commitment = bet.commitment;
        amount = bet.amount;
        betType = bet.betType;
        betData = bet.betData;
        commitBlock = bet.commitBlock;
        settled = bet.settled;

        if (commitment != bytes32(0) && !settled) {
            canReveal =
                block.number >= commitBlock + MIN_REVEAL_DELAY && block.number <= commitBlock + MAX_REVEAL_DELAY;
            isExpired = block.number > commitBlock + MAX_REVEAL_DELAY;
        }
    }

    /// @notice Calculate commitment hash for a secret (helper for frontend)
    /// @param secret The secret to hash
    /// @return commitment The keccak256 hash
    function calculateCommitment(bytes32 secret) external pure returns (bytes32 commitment) {
        commitment = keccak256(abi.encodePacked(secret));
    }

    /// @notice Get payout multiplier for a bet type
    /// @param betType The bet type
    /// @return multiplier The payout multiplier (e.g., 35 for 35:1)
    function getPayoutMultiplier(BetTypes.BetType betType) external pure returns (uint256 multiplier) {
        multiplier = BetTypes.getPayout(betType);
    }

    /// @notice Check if a result would win for a given bet
    /// @param result The roulette result (0-36)
    /// @param betType The bet type
    /// @param betData The bet data
    /// @return won Whether the bet would win
    function checkWinCondition(uint8 result, BetTypes.BetType betType, uint256 betData)
        external
        pure
        returns (bool won)
    {
        won = BetTypes.checkWin(result, betType, betData);
    }
}
