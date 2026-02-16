// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title ERC4906 Agent Extension v1.1 (Remediated)
/// @notice EIP-4906 metadata update with agent signing and hash-based nonces
contract ERC4906AgentExtension is EIP712 {
    using ECDSA for bytes32;
    
    // ============ CONSTANTS ============
    bytes32 private constant _UPDATE_TYPEHASH = keccak256(
        "UpdateRequest(address agent,uint256 tokenId,string metadataURI,bytes32 nonceHash,uint256 deadline)"
    );
    
    // ============ STATE VARIABLES ============
    mapping(bytes32 => bool) public nonceHashes;
    mapping(address => bool) public authorizedAgents;
    
    IERC721 public immutable targetNFT;
    
    event MetadataUpdated(uint256 indexed tokenId, string metadataURI, address indexed agent);
    event NonceRevealed(bytes32 indexed nonceHash, uint256 nonce);
    event AgentAuthorized(address indexed agent);
    event AgentRevoked(address indexed agent);
    
    // ============ CONSTRUCTOR ============
    constructor(address _targetNFT) EIP712("ERC4906AgentExtension", "1.1") {
        targetNFT = IERC721(_targetNFT);
        // Domain separator now includes block.chainid via EIP712 parent
    }
    
    // ============ AGENT MANAGEMENT ============
    function authorizeAgent(address agent) external {
        require(msg.sender == address(targetNFT), "Only NFT contract");
        authorizedAgents[agent] = true;
        emit AgentAuthorized(agent);
    }
    
    function revokeAgent(address agent) external {
        require(msg.sender == address(targetNFT), "Only NFT contract");
        authorizedAgents[agent] = false;
        emit AgentRevoked(agent);
    }
    
    // ============ METADATA UPDATE ============
    /// @notice Update metadata with EIP-712 signature
    function updateMetadataWithSig(
        address agent,
        uint256 tokenId,
        string calldata metadataURI,
        bytes32 nonceHash,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(block.timestamp <= deadline, "Signature expired");
        require(!nonceHashes[nonceHash], "Nonce already used");
        require(authorizedAgents[agent], "Agent not authorized");
        
        // Verify signature
        bytes32 structHash = keccak256(abi.encode(
            _UPDATE_TYPEHASH,
            agent,
            tokenId,
            keccak256(bytes(metadataURI)),
            nonceHash,
            deadline
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredAddress = digest.recover(signature);
        require(recoveredAddress != address(0), "Invalid signature"); // CRITICAL FIX
        require(recoveredAddress == agent, "Invalid signer");
        
        // Mark nonce hash as used
        nonceHashes[nonceHash] = true;
        
        // Emit EIP-4906 event
        emit MetadataUpdated(tokenId, metadataURI, agent);
    }
    
    /// @notice Reveal nonce to enable future updates
    function revealNonce(bytes32 nonceHash, uint256 nonce) external {
        require(authorizedAgents[msg.sender], "Unauthorized");
        require(keccak256(abi.encodePacked(nonce, msg.sender)) == nonceHash, "Invalid reveal");
        require(!nonceHashes[nonceHash], "Nonce already used");
        
        nonceHashes[nonceHash] = true;
        emit NonceRevealed(nonceHash, nonce);
    }
    
    /// @notice Generate nonce hash for front-running protection
    function generateNonceHash(uint256 nonce, address agent) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(nonce, agent));
    }
}
