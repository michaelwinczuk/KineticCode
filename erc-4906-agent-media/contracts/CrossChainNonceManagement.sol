// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Cross-Chain Nonce Management v1.2 (Patched - CCNM-003)
/// @notice Manages nonce consumption across multiple chains with Merkle proof verification
/// @dev updateStateRoot restricted to owner only - fixes CCNM-003 Nomad Bridge pattern
contract CrossChainNonceManagement is Ownable {

    // ============ STATE VARIABLES ============
    /// @notice sourceChainId => nonce => consumed
    mapping(uint256 => mapping(uint256 => bool)) public consumedNonces;

    /// @notice Current trusted Merkle state root
    bytes32 public stateRoot;

    // ============ EVENTS ============
    event NonceConsumed(uint256 indexed sourceChainId, uint256 nonce);
    event StateRootUpdated(bytes32 newRoot, uint256 timestamp);

    // ============ CONSTRUCTOR ============
    /// @param _initialStateRoot Initial trusted Merkle state root
    constructor(bytes32 _initialStateRoot) {
        stateRoot = _initialStateRoot;
    }

    // ============ STATE MANAGEMENT ============
    /// @notice Update the trusted Merkle state root
    /// @dev onlyOwner prevents Nomad Bridge pattern exploit (CCNM-003)
    /// @param _newRoot New Merkle state root from authorized cross-chain bridge
    function updateStateRoot(bytes32 _newRoot) external onlyOwner {
        stateRoot = _newRoot;
        emit StateRootUpdated(_newRoot, block.timestamp);
    }

    // ============ NONCE CONSUMPTION ============
    /// @notice Consume nonce with Merkle proof verification
    /// @param sourceChainId The chain ID where the nonce originated
    /// @param nonce The nonce value to consume
    /// @param proof Merkle proof validating this nonce against state root
    function consumeNonceWithProof(
        uint256 sourceChainId,
        uint256 nonce,
        bytes32[] calldata proof
    ) external {
        require(!consumedNonces[sourceChainId][nonce], "Nonce already consumed");

        bytes32 leaf = keccak256(abi.encodePacked(sourceChainId, nonce));
        require(_verifyStateProof(leaf, proof), "Invalid state proof");

        consumedNonces[sourceChainId][nonce] = true;
        emit NonceConsumed(sourceChainId, nonce);
    }

    /// @notice Verify Merkle proof against current state root
    /// @param leaf The leaf node to verify
    /// @param proof The Merkle proof
    /// @return valid True if proof is valid
    function _verifyStateProof(bytes32 leaf, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        return MerkleProof.verify(proof, stateRoot, leaf);
    }

    /// @notice Check if a nonce has been consumed
    /// @param sourceChainId The source chain ID
    /// @param nonce The nonce to check
    /// @return True if already consumed
    function isNonceConsumed(uint256 sourceChainId, uint256 nonce)
        external
        view
        returns (bool)
    {
        return consumedNonces[sourceChainId][nonce];
    }
}