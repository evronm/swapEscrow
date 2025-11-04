// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title Escrow
 * @notice Single-use escrow contract for atomic swaps with time locks
 * @dev Just transfer assets to the contract. Call process() after ERC20 transfers.
 *      First asset starts timer. Payment matching params triggers swap. Expiry returns assets.
 */
contract Escrow is IERC721Receiver, IERC1155Receiver {
    // Custom errors
    error AlreadyInitialized();
    error NotInitialized();
    error EscrowExpired();
    error EscrowNotExpired();
    error EscrowAlreadyCompleted();
    error NoAssetsDeposited();
    error TransferFailed();
    error NothingToProcess();

    enum AssetType { ERC20, ERC721, ERC1155 }

    struct DepositedAsset {
        AssetType assetType;
        address tokenAddress;
        uint256 tokenId;      // Used for ERC721 and ERC1155
        uint256 amount;       // Used for ERC20 and ERC1155
        address depositor;
    }

    // Escrow configuration
    uint256 public duration;
    AssetType public paymentAssetType;
    address public paymentToken;
    uint256 public paymentTokenId;    // Used for ERC721 and ERC1155
    uint256 public paymentAmount;     // Used for ERC20 and ERC1155

    // Escrow state
    bool public initialized;
    bool public completed;
    uint256 public expiryTime;
    address public firstDepositor;
    DepositedAsset[] public depositedAssets;

    // Track processed ERC20 balances to avoid double-counting
    mapping(address => uint256) public processedERC20;

    /**
     * @notice Initialize the escrow contract (called by factory)
     * @param _duration Time lock duration in seconds
     * @param _paymentAssetType Type of asset expected as payment (0=ERC20, 1=ERC721, 2=ERC1155)
     * @param _paymentToken Address of the token expected as payment
     * @param _paymentTokenId Token ID for ERC721/ERC1155 payment (0 for ERC20)
     * @param _paymentAmount Amount for ERC20/ERC1155 payment (ignored for ERC721)
     */
    function initialize(
        uint256 _duration,
        AssetType _paymentAssetType,
        address _paymentToken,
        uint256 _paymentTokenId,
        uint256 _paymentAmount
    ) external {
        if (initialized) revert AlreadyInitialized();

        duration = _duration;
        paymentAssetType = _paymentAssetType;
        paymentToken = _paymentToken;
        paymentTokenId = _paymentTokenId;
        paymentAmount = _paymentAmount;
        initialized = true;
    }

    /**
     * @notice Process any ERC20 tokens that have been transferred to this contract
     * @dev Call this after ERC20 transfers to detect and handle deposits or payments
     * @param token The ERC20 token address to check
     * @param depositor The address to credit as depositor (for deposits only, ignored for payments)
     */
    function process(address token, address depositor) external {
        if (!initialized) revert NotInitialized();
        if (completed) revert EscrowAlreadyCompleted();

        // Check current balance vs processed balance
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        uint256 alreadyProcessed = processedERC20[token];

        if (currentBalance <= alreadyProcessed) revert NothingToProcess();

        uint256 newAmount = currentBalance - alreadyProcessed;

        // If expired, only accept as deposit (payment window closed)
        bool isExpired = expiryTime != 0 && block.timestamp >= expiryTime;

        // Check if this matches payment parameters (only before expiry)
        if (!isExpired && _isPayment(AssetType.ERC20, token, 0, newAmount)) {
            // Mark as processed first (before swap to prevent reentrancy)
            processedERC20[token] = currentBalance;
            _executeSwap(depositor); // depositor here is actually the payer
        } else {
            // It's a deposit - add to locked assets
            processedERC20[token] = currentBalance;
            _addDeposit(AssetType.ERC20, token, 0, newAmount, depositor);
        }
    }

    /**
     * @notice Withdraw all assets after expiry (if payment wasn't received)
     */
    function withdrawExpired() external {
        if (!initialized) revert NotInitialized();
        if (completed) revert EscrowAlreadyCompleted();
        if (depositedAssets.length == 0) revert NoAssetsDeposited();
        if (block.timestamp < expiryTime) revert EscrowNotExpired();

        // Mark as completed first to prevent reentrancy
        completed = true;

        // Return all assets to their original depositors
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            DepositedAsset memory asset = depositedAssets[i];
            _transferAsset(asset, asset.depositor);
        }
    }

    /**
     * @notice Get the number of deposited assets
     */
    function getDepositedAssetsCount() external view returns (uint256) {
        return depositedAssets.length;
    }

    /**
     * @notice Get a specific deposited asset by index
     */
    function getDepositedAsset(uint256 index) external view returns (DepositedAsset memory) {
        return depositedAssets[index];
    }

    /**
     * @dev Check if the given asset matches the payment parameters
     */
    function _isPayment(
        AssetType assetType,
        address token,
        uint256 tokenId,
        uint256 amount
    ) internal view returns (bool) {
        // Must have deposits to pay for
        if (depositedAssets.length == 0) return false;

        // Check if asset type matches
        if (assetType != paymentAssetType) return false;

        // Check if token address matches
        if (token != paymentToken) return false;

        // For ERC721, check token ID
        if (assetType == AssetType.ERC721 && tokenId != paymentTokenId) return false;

        // For ERC1155, check both token ID and amount
        if (assetType == AssetType.ERC1155) {
            if (tokenId != paymentTokenId || amount != paymentAmount) return false;
        }

        // For ERC20, check amount
        if (assetType == AssetType.ERC20 && amount != paymentAmount) return false;

        return true;
    }

    /**
     * @dev Add an asset to the deposited assets list
     */
    function _addDeposit(
        AssetType assetType,
        address token,
        uint256 tokenId,
        uint256 amount,
        address depositor
    ) internal {
        // Start timer on first deposit
        if (depositedAssets.length == 0) {
            expiryTime = block.timestamp + duration;
            firstDepositor = depositor;
        }

        // Record the deposit
        depositedAssets.push(DepositedAsset({
            assetType: assetType,
            tokenAddress: token,
            tokenId: tokenId,
            amount: amount,
            depositor: depositor
        }));
    }

    /**
     * @dev Execute the swap: transfer payment to first depositor, transfer all assets to payer
     */
    function _executeSwap(address payer) internal {
        if (depositedAssets.length == 0) revert NoAssetsDeposited();

        // Mark as completed first to prevent reentrancy
        completed = true;

        // Transfer payment to first depositor
        if (paymentAssetType == AssetType.ERC20) {
            bool success = IERC20(paymentToken).transfer(firstDepositor, paymentAmount);
            if (!success) revert TransferFailed();
        } else if (paymentAssetType == AssetType.ERC721) {
            IERC721(paymentToken).safeTransferFrom(address(this), firstDepositor, paymentTokenId);
        } else if (paymentAssetType == AssetType.ERC1155) {
            IERC1155(paymentToken).safeTransferFrom(
                address(this),
                firstDepositor,
                paymentTokenId,
                paymentAmount,
                ""
            );
        }

        // Transfer all deposited assets to payer
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            _transferAsset(depositedAssets[i], payer);
        }
    }

    /**
     * @dev Transfer a single asset to recipient
     */
    function _transferAsset(DepositedAsset memory asset, address recipient) internal {
        if (asset.assetType == AssetType.ERC20) {
            bool success = IERC20(asset.tokenAddress).transfer(recipient, asset.amount);
            if (!success) revert TransferFailed();
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.tokenAddress).safeTransferFrom(address(this), recipient, asset.tokenId);
        } else if (asset.assetType == AssetType.ERC1155) {
            IERC1155(asset.tokenAddress).safeTransferFrom(
                address(this),
                recipient,
                asset.tokenId,
                asset.amount,
                ""
            );
        }
    }

    // ERC721 Receiver - automatically handles incoming NFTs
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (!initialized) revert NotInitialized();
        if (completed) revert EscrowAlreadyCompleted();

        bool isExpired = expiryTime != 0 && block.timestamp >= expiryTime;

        // Check if this is payment or deposit (only accept payment before expiry)
        if (!isExpired && _isPayment(AssetType.ERC721, msg.sender, tokenId, 1)) {
            _executeSwap(from);
        } else {
            _addDeposit(AssetType.ERC721, msg.sender, tokenId, 1, from);
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    // ERC1155 Receiver - automatically handles incoming tokens
    function onERC1155Received(
        address,
        address from,
        uint256 tokenId,
        uint256 amount,
        bytes calldata
    ) external override returns (bytes4) {
        if (!initialized) revert NotInitialized();
        if (completed) revert EscrowAlreadyCompleted();

        bool isExpired = expiryTime != 0 && block.timestamp >= expiryTime;

        // Check if this is payment or deposit (only accept payment before expiry)
        if (!isExpired && _isPayment(AssetType.ERC1155, msg.sender, tokenId, amount)) {
            _executeSwap(from);
        } else {
            _addDeposit(AssetType.ERC1155, msg.sender, tokenId, amount, from);
        }

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        // Batch transfers not supported for simplicity
        revert("Batch transfers not supported");
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
