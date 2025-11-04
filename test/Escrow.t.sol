// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/EscrowFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// Mock tokens for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("Mock NFT", "MNFT") {}

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://mock.uri/{id}") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

contract EscrowTest is Test {
    EscrowFactory factory;
    MockERC20 token;
    MockERC721 nft;
    MockERC1155 multiToken;

    address seller = address(0x1);
    address buyer = address(0x2);
    address other = address(0x3);

    function setUp() public {
        factory = new EscrowFactory();
        token = new MockERC20();
        nft = new MockERC721();
        multiToken = new MockERC1155();

        // Setup balances
        token.mint(seller, 1000 ether);
        token.mint(buyer, 1000 ether);
        nft.mint(seller);
        nft.mint(seller);
        nft.mint(buyer);
        multiToken.mint(seller, 1, 100);
        multiToken.mint(buyer, 2, 100);
    }

    function testERC721ForERC20Swap() public {
        // Create escrow: expects 100 tokens as payment
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.startPrank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);
        vm.stopPrank();

        // Verify deposit
        assertEq(escrow.getDepositedAssetsCount(), 1);
        assertEq(escrow.firstDepositor(), seller);
        assertTrue(escrow.expiryTime() > 0);

        // Buyer sends payment
        vm.startPrank(buyer);
        token.transfer(escrowAddr, 100 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        // Verify swap completed
        assertTrue(escrow.completed());
        assertEq(nft.ownerOf(0), buyer);
        assertEq(token.balanceOf(seller), 1100 ether);
    }

    function testMultipleNFTsForERC20() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            200 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits multiple NFTs
        vm.startPrank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);
        nft.safeTransferFrom(seller, escrowAddr, 1);
        vm.stopPrank();

        assertEq(escrow.getDepositedAssetsCount(), 2);

        // Buyer pays
        vm.startPrank(buyer);
        token.transfer(escrowAddr, 200 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        // Verify both NFTs transferred
        assertTrue(escrow.completed());
        assertEq(nft.ownerOf(0), buyer);
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), 1200 ether);
    }

    function testERC721ForERC721Swap() public {
        // Create escrow: expects NFT tokenId 2 as payment
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC721,
            address(nft),
            2,
            0
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT 0
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Buyer sends NFT 2 as payment
        vm.prank(buyer);
        nft.safeTransferFrom(buyer, escrowAddr, 2);

        // Verify swap
        assertTrue(escrow.completed());
        assertEq(nft.ownerOf(0), buyer);
        assertEq(nft.ownerOf(2), seller);
    }

    function testERC1155ForERC1155Swap() public {
        // Create escrow: expects 50 of token ID 2
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC1155,
            address(multiToken),
            2,
            50
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits 100 of token ID 1
        vm.prank(seller);
        multiToken.safeTransferFrom(seller, escrowAddr, 1, 100, "");

        assertEq(escrow.getDepositedAssetsCount(), 1);

        // Buyer sends 50 of token ID 2 as payment
        vm.prank(buyer);
        multiToken.safeTransferFrom(buyer, escrowAddr, 2, 50, "");

        // Verify swap
        assertTrue(escrow.completed());
        assertEq(multiToken.balanceOf(buyer, 1), 100);
        assertEq(multiToken.balanceOf(seller, 2), 50);
    }

    function testExpiredWithdrawal() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 hours,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Withdraw
        escrow.withdrawExpired();

        // Verify NFT returned to seller
        assertTrue(escrow.completed());
        assertEq(nft.ownerOf(0), seller);
    }

    function testCannotPayAfterExpiry() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 hours,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Try to pay - should just add as deposit, not trigger swap
        vm.startPrank(buyer);
        token.transfer(escrowAddr, 100 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        // Should not be completed (payment rejected after expiry)
        assertFalse(escrow.completed());
        assertEq(escrow.getDepositedAssetsCount(), 2); // NFT + ERC20 deposit
    }

    function testProcessAfterExpiryTracksDeposit() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 hours,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Someone sends tokens after expiry
        vm.prank(buyer);
        token.transfer(escrowAddr, 50 ether);

        escrow.process(address(token), buyer);

        // Should be tracked as deposit
        assertEq(escrow.getDepositedAssetsCount(), 2);

        // Withdraw should return both
        escrow.withdrawExpired();
        assertEq(nft.ownerOf(0), seller);
        assertEq(token.balanceOf(buyer), 1000 ether - 50 ether + 50 ether); // Got refund
    }

    function testWrongPaymentAmount() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Buyer sends wrong amount - should be treated as deposit
        vm.startPrank(buyer);
        token.transfer(escrowAddr, 50 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        // Should not complete swap
        assertFalse(escrow.completed());
        assertEq(escrow.getDepositedAssetsCount(), 2);
    }

    function testCannotWithdrawBeforeExpiry() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Seller deposits NFT
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        // Try to withdraw before expiry
        vm.expectRevert(Escrow.EscrowNotExpired.selector);
        escrow.withdrawExpired();
    }

    function testMultipleERC20Deposits() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // First seller deposits some tokens
        vm.startPrank(seller);
        token.transfer(escrowAddr, 50 ether);
        escrow.process(address(token), seller);
        vm.stopPrank();

        // Second seller deposits more tokens
        vm.startPrank(other);
        token.mint(other, 100 ether);
        token.transfer(escrowAddr, 30 ether);
        escrow.process(address(token), other);
        vm.stopPrank();

        assertEq(escrow.getDepositedAssetsCount(), 2);
        assertEq(escrow.firstDepositor(), seller);

        // Buyer pays exact amount
        vm.startPrank(buyer);
        token.transfer(escrowAddr, 100 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        // Verify payment went to first depositor
        assertTrue(escrow.completed());
        assertEq(token.balanceOf(seller), 1050 ether); // 1000 - 50 (deposited) + 100 (payment)

        // Buyer should receive all deposited tokens
        assertEq(token.balanceOf(buyer), 1000 ether - 100 ether + 50 ether + 30 ether);
    }

    function testNothingToProcess() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Try to process without any transfers
        vm.expectRevert(Escrow.NothingToProcess.selector);
        escrow.process(address(token), buyer);
    }

    function testCannotDepositAfterCompletion() public {
        // Create escrow
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );
        Escrow escrow = Escrow(escrowAddr);

        // Complete the escrow
        vm.prank(seller);
        nft.safeTransferFrom(seller, escrowAddr, 0);

        vm.startPrank(buyer);
        token.transfer(escrowAddr, 100 ether);
        escrow.process(address(token), buyer);
        vm.stopPrank();

        assertTrue(escrow.completed());

        // Try to deposit after completion
        vm.prank(seller);
        vm.expectRevert(Escrow.EscrowAlreadyCompleted.selector);
        nft.safeTransferFrom(seller, escrowAddr, 1);
    }
}
