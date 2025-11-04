# SwapEscrow

A minimal, gas-optimized escrow system for trustless atomic swaps on Ethereum. Built with Solidity ^0.8.20 and Foundry.

## Features

✅ **Multi-Token Support** - ERC20, ERC721, and ERC1155 tokens
✅ **Automatic Detection** - Just transfer tokens to the contract
✅ **Time-Locked Swaps** - First deposit starts timer, expiry returns assets
✅ **Multiple Assets** - Lock multiple NFTs/tokens in a single escrow
✅ **DAO Compatible** - Works with simple `token.transfer()` calls
✅ **Gas Optimized** - EIP-1167 minimal proxy pattern (~90% gas savings)
✅ **Reentrancy Protected** - CEI pattern enforced throughout
✅ **Fully Tested** - 20 comprehensive test cases

## How It Works

1. **Deploy** - Use `EscrowFactory` to create a new escrow with payment parameters
2. **Deposit** - Seller transfers assets to the escrow (NFTs/tokens)
3. **Pay** - Buyer transfers payment to the escrow
4. **Swap** - Assets automatically exchanged when payment matches parameters
5. **Expiry** - If no payment, assets return to depositors after time lock

## Quick Start

### Installation

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

```solidity
// Deploy the factory
EscrowFactory factory = new EscrowFactory();

// Create an escrow: 1 day duration, expecting 100 USDC
address escrowAddr = factory.createEscrow(
    1 days,                     // Duration
    Escrow.AssetType.ERC20,     // Payment type
    address(usdcToken),         // Payment token
    0,                          // Token ID (for ERC721/1155)
    100 * 10**6                 // Payment amount (100 USDC)
);
```

## Usage Examples

### Example 1: NFT for ERC20

```solidity
// Seller deposits NFT
nft.safeTransferFrom(seller, escrowAddr, tokenId);

// Buyer pays with ERC20
usdc.transfer(escrowAddr, 100 * 10**6);
escrow.process(address(usdc), buyer);

// Swap complete! Buyer receives NFT, seller receives USDC
```

### Example 2: Multiple NFTs for ERC20

```solidity
// Seller deposits multiple NFTs
nft.safeTransferFrom(seller, escrowAddr, tokenId1);
nft.safeTransferFrom(seller, escrowAddr, tokenId2);
nft.safeTransferFrom(seller, escrowAddr, tokenId3);

// Buyer pays once
usdc.transfer(escrowAddr, 500 * 10**6);
escrow.process(address(usdc), buyer);

// Buyer receives all 3 NFTs!
```

### Example 3: NFT for NFT

```solidity
// Create escrow expecting NFT #42 as payment
address escrowAddr = factory.createEscrow(
    1 days,
    Escrow.AssetType.ERC721,
    address(bayc),
    42,  // Token ID
    0
);

// Seller deposits their NFT
coolCats.safeTransferFrom(seller, escrowAddr, 123);

// Buyer sends their NFT as payment
bayc.safeTransferFrom(buyer, escrowAddr, 42);

// Swap complete!
```

### Example 4: DAO Purchase

```solidity
// DAO creates escrow for an NFT purchase
address escrowAddr = factory.createEscrow(
    7 days,
    Escrow.AssetType.ERC20,
    address(daoToken),
    0,
    1000 ether
);

// Seller deposits NFT
nft.safeTransferFrom(seller, escrowAddr, tokenId);

// DAO votes and executes treasury proposal
// Proposal calls: daoToken.transfer(escrowAddr, 1000 ether)
// Then someone calls: escrow.process(address(daoToken), daoAddress)

// DAO receives the NFT!
```

### Example 5: Expired Escrow

```solidity
// Seller deposits NFT
nft.safeTransferFrom(seller, escrowAddr, tokenId);

// Time passes... buyer never pays
// After expiry, anyone can trigger withdrawal

escrow.withdrawExpired();

// NFT returned to seller
```

## Contract Architecture

### Escrow.sol

Single-use escrow contract for atomic swaps. Supports:
- ERC20, ERC721, and ERC1155 tokens
- Multiple asset deposits
- Automatic payment detection
- Time-locked expiry

**Key Functions:**
- `process(token, depositor)` - Process ERC20 deposits/payments
- `withdrawExpired()` - Return assets after expiry
- `onERC721Received()` / `onERC1155Received()` - Auto-handle NFTs

### EscrowFactory.sol

Factory for deploying minimal proxy clones of escrow contracts.

**Key Functions:**
- `createEscrow(duration, paymentType, token, tokenId, amount)` - Deploy new escrow
- `getEscrow(escrowId)` - Get escrow address by ID

## Security

- ✅ **Reentrancy Protection** - Checks-Effects-Interactions pattern
- ✅ **No Admin Keys** - Fully trustless, no owner privileges
- ✅ **OpenZeppelin Contracts** - Industry-standard token interfaces
- ✅ **Comprehensive Tests** - Edge cases and attack vectors covered

## Gas Costs

- Factory deployment: ~400k gas
- Escrow creation: ~150k gas (90% cheaper than direct deployment)
- Swap execution: ~200k-300k gas depending on token types

## Development

### Project Structure

```
swapEscrow/
├── src/
│   ├── Escrow.sol         # Main escrow contract
│   └── EscrowFactory.sol  # Factory for deploying escrows
├── test/
│   ├── Escrow.t.sol       # Escrow tests
│   └── EscrowFactory.t.sol # Factory tests
├── lib/                    # Dependencies (forge-std, OpenZeppelin)
└── foundry.toml            # Foundry config
```

### Running Tests

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testERC721ForERC20Swap

# Run with gas reporting
forge test --gas-report

# Run with verbosity
forge test -vvv
```

### Code Coverage

```bash
forge coverage
```

## Use Cases

- 🎨 **NFT Marketplaces** - P2P NFT sales with escrow protection
- 🏛️ **DAO Purchases** - Safe asset purchases through governance
- 💱 **Token Swaps** - OTC trades with time-locked security
- 🎮 **Gaming Assets** - In-game item trading
- 🖼️ **Art Deals** - Multi-asset bundle trades

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

## Contact

Built for the MarketDAO ecosystem and beyond.
