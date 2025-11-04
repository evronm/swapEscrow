// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Escrow.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title EscrowFactory
 * @notice Factory for deploying minimal escrow contracts using the clone pattern
 * @dev Uses EIP-1167 minimal proxy pattern to save deployment gas
 */
contract EscrowFactory {
    // Implementation contract for cloning
    address public immutable escrowImplementation;

    // Track all deployed escrows
    mapping(uint256 => address) public escrows;
    uint256 public escrowCount;

    // Events
    event EscrowCreated(
        address indexed escrow,
        uint256 indexed escrowId,
        address indexed creator,
        uint256 duration,
        Escrow.AssetType paymentAssetType,
        address paymentToken,
        uint256 paymentTokenId,
        uint256 paymentAmount
    );

    constructor() {
        // Deploy implementation contract once
        escrowImplementation = address(new Escrow());
    }

    /**
     * @notice Create a new escrow contract
     * @param duration Time lock duration in seconds
     * @param paymentAssetType Type of asset expected as payment (0=ERC20, 1=ERC721, 2=ERC1155)
     * @param paymentToken Address of the token expected as payment
     * @param paymentTokenId Token ID for ERC721/ERC1155 payment (0 for ERC20)
     * @param paymentAmount Amount for ERC20/ERC1155 payment (ignored for ERC721)
     * @return The address of the newly created escrow contract
     */
    function createEscrow(
        uint256 duration,
        Escrow.AssetType paymentAssetType,
        address paymentToken,
        uint256 paymentTokenId,
        uint256 paymentAmount
    ) external returns (address) {
        // Clone the implementation
        address clone = Clones.clone(escrowImplementation);

        // Initialize the escrow
        Escrow(clone).initialize(
            duration,
            paymentAssetType,
            paymentToken,
            paymentTokenId,
            paymentAmount
        );

        // Track the escrow
        uint256 escrowId = escrowCount++;
        escrows[escrowId] = clone;

        emit EscrowCreated(
            clone,
            escrowId,
            msg.sender,
            duration,
            paymentAssetType,
            paymentToken,
            paymentTokenId,
            paymentAmount
        );

        return clone;
    }

    /**
     * @notice Get an escrow address by its ID
     * @param escrowId The ID of the escrow
     * @return The address of the escrow contract
     */
    function getEscrow(uint256 escrowId) external view returns (address) {
        require(escrowId < escrowCount, "Invalid escrow ID");
        return escrows[escrowId];
    }
}
