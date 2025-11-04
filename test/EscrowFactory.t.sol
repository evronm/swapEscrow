// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/EscrowFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract EscrowFactoryTest is Test {
    EscrowFactory factory;
    MockERC20 token;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        factory = new EscrowFactory();
        token = new MockERC20();
    }

    function testFactoryDeploysImplementation() public {
        assertTrue(factory.escrowImplementation() != address(0));
    }

    function testCreateEscrow() public {
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        assertTrue(escrowAddr != address(0));
        assertEq(factory.escrowCount(), 1);
        assertEq(factory.escrows(0), escrowAddr);
    }

    function testGetEscrow() public {
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        assertEq(factory.getEscrow(0), escrowAddr);
    }

    function testMultipleEscrows() public {
        address escrow1 = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        address escrow2 = factory.createEscrow(
            2 days,
            Escrow.AssetType.ERC721,
            address(token),
            5,
            0
        );

        address escrow3 = factory.createEscrow(
            3 days,
            Escrow.AssetType.ERC1155,
            address(token),
            10,
            50
        );

        assertEq(factory.escrowCount(), 3);
        assertEq(factory.getEscrow(0), escrow1);
        assertEq(factory.getEscrow(1), escrow2);
        assertEq(factory.getEscrow(2), escrow3);

        // Verify each escrow is initialized correctly
        Escrow e1 = Escrow(escrow1);
        assertEq(e1.duration(), 1 days);
        assertEq(uint(e1.paymentAssetType()), uint(Escrow.AssetType.ERC20));
        assertEq(e1.paymentAmount(), 100 ether);

        Escrow e2 = Escrow(escrow2);
        assertEq(e2.duration(), 2 days);
        assertEq(uint(e2.paymentAssetType()), uint(Escrow.AssetType.ERC721));
        assertEq(e2.paymentTokenId(), 5);

        Escrow e3 = Escrow(escrow3);
        assertEq(e3.duration(), 3 days);
        assertEq(uint(e3.paymentAssetType()), uint(Escrow.AssetType.ERC1155));
        assertEq(e3.paymentTokenId(), 10);
        assertEq(e3.paymentAmount(), 50);
    }

    function testEscrowsAreIndependent() public {
        address escrow1 = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        address escrow2 = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            200 ether
        );

        // Verify they are different contracts
        assertTrue(escrow1 != escrow2);

        // Verify they have independent state
        Escrow e1 = Escrow(escrow1);
        Escrow e2 = Escrow(escrow2);

        assertEq(e1.paymentAmount(), 100 ether);
        assertEq(e2.paymentAmount(), 200 ether);
    }

    function testCannotGetInvalidEscrow() public {
        vm.expectRevert("Invalid escrow ID");
        factory.getEscrow(0);

        factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        vm.expectRevert("Invalid escrow ID");
        factory.getEscrow(1);
    }

    function testEscrowCreatedEvent() public {
        // Record logs to verify event emission
        vm.recordLogs();
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EscrowCreated(address,uint256,address,uint256,uint8,address,uint256,uint256)"));

        // Verify the escrow address in the event matches what was returned
        address eventEscrow = abi.decode(abi.encodePacked(entries[0].topics[1]), (address));
        assertEq(eventEscrow, escrowAddr);
    }

    function testEscrowCannotBeInitializedTwice() public {
        address escrowAddr = factory.createEscrow(
            1 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            100 ether
        );

        Escrow escrow = Escrow(escrowAddr);

        vm.expectRevert(Escrow.AlreadyInitialized.selector);
        escrow.initialize(
            2 days,
            Escrow.AssetType.ERC20,
            address(token),
            0,
            200 ether
        );
    }
}
