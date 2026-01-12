# JuiceRoule

Fully decentralized on-chain European roulette for Citrea (EVM). No oracle, no operator - pure smart contract randomness using commit-reveal + future blockhash.

## Features

- **100% On-Chain**: No external dependencies, no oracles
- **Trustless**: Commit-reveal scheme ensures fair randomness
- **Liquidity Pool**: Anyone can become the house by providing liquidity
- **Full Roulette**: All European roulette bet types (35:1 down to 1:1)
- **2.7% House Edge**: Natural edge from the zero (European roulette)

## How It Works

### Randomness Mechanism

```
Block N:     Player calls placeBet() with commitment = hash(secret)
Block N+2:   Player calls revealAndSettle() with secret
             → random = keccak256(secret, blockhash(N+1)) % 37
Block N+250: If player doesn't reveal → forceSettle() (player loses)
```

### Security

1. **Player can't cheat**: Doesn't know future blockhash when committing
2. **Miner can't cheat**: Doesn't know player's secret
3. **No operator**: Pure smart contract logic
4. **Timeout protection**: Non-reveal = automatic loss

## Bet Types

| Bet Type | Numbers | Payout | Description |
|----------|---------|--------|-------------|
| Straight Up | 1 | 35:1 | Single number (0-36) |
| Split | 2 | 17:1 | Two adjacent numbers |
| Street | 3 | 11:1 | Three numbers in a row |
| Corner | 4 | 8:1 | Four numbers in a square |
| Six Line | 6 | 5:1 | Two adjacent rows |
| Column | 12 | 2:1 | Vertical column |
| Dozen | 12 | 2:1 | 1-12, 13-24, or 25-36 |
| Red/Black | 18 | 1:1 | Color bet |
| Odd/Even | 18 | 1:1 | Parity bet |
| High/Low | 18 | 1:1 | 1-18 or 19-36 |

## Installation

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and build
git clone https://github.com/YOUR_USERNAME/juiceroule.git
cd juiceroule
forge install
forge build
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_PlaceBet_StraightUp

# Run fuzz tests with more runs
forge test --fuzz-runs 10000
```

## Deployment

### Local (Anvil)

```bash
# Start local node
anvil

# Deploy
forge script script/Counter.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast
```

### Citrea Testnet

```bash
# Set environment
export PRIVATE_KEY=your_private_key
export RPC_URL=https://rpc.testnet.citrea.xyz

# Deploy
forge script script/Counter.s.sol:Deploy --rpc-url $RPC_URL --broadcast

# Deploy with initial liquidity
INITIAL_LIQUIDITY=10000000000000000000 forge script script/Counter.s.sol:DeployWithLiquidity --rpc-url $RPC_URL --broadcast
```

## Usage

### For Players

```solidity
// 1. Generate a secret locally
bytes32 secret = keccak256(abi.encodePacked(block.timestamp, msg.sender, randomSalt));
bytes32 commitment = keccak256(abi.encodePacked(secret));

// 2. Place bet (e.g., bet on Red)
roulette.placeBet{value: 0.1 ether}(commitment, BetType.RED, 0);

// 3. Wait 2+ blocks, then reveal
roulette.revealAndSettle(secret);
```

### For Liquidity Providers

```solidity
// Deposit ETH to earn from house edge
pool.deposit{value: 10 ether}();

// Withdraw (proportional to pool performance)
pool.withdraw(pool.balanceOf(msg.sender));
```

## Contract Addresses

| Network | JuiceRoule | LiquidityPool |
|---------|------------|---------------|
| Citrea Testnet | TBD | TBD |
| Citrea Mainnet | TBD | TBD |

## Architecture

```
src/
├── JuiceRoule.sol          # Main game logic
├── LiquidityPool.sol       # ERC20 vault for liquidity providers
└── libraries/
    └── BetTypes.sol        # Bet validation and payout logic
```

## Security Considerations

- **Max Bet**: Limited to 1% of available pool liquidity
- **Blockhash Limit**: Bets expire after 250 blocks (blockhash only available for 256)
- **Reentrancy**: Protected with OpenZeppelin ReentrancyGuard
- **Locked Funds**: Pool tracks potential payouts to prevent insolvency

## License

MIT
