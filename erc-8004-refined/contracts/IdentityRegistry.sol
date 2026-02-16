// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "./IERC6551Registry.sol"; // Interface for ERC-6551 registry

contract IdentityRegistry is ERC721Upgradeable, ERC721URIStorageUpgradeable, EIP712Upgradeable {
    /// @dev Struct to store agent wallet mapping
    struct AgentWallet {
        address wallet;
        uint256 setTimestamp;
    }

    /// @dev Mapping from agentId to AgentWallet
    mapping(uint256 => AgentWallet) private _agentWallets;
    
    /// @dev Mapping from agent ID to a key-value store for metadata
    mapping(uint256 => mapping(string => string)) private _agentMetadata;
    
    /// @dev Nonce tracking for replay protection
    mapping(uint256 => uint256) private _nonces;

    /// @dev ERC-6551 registry address for TBA validation
    address public erc6551Registry;
    
    /// @dev Modifier to check if caller owns the agent NFT
    modifier onlyOwnerOf(uint256 agentId) {
        require(ownerOf(agentId) == msg.sender, "IdentityRegistry: caller is not owner");
        _;
    }

    /// @dev EIP-712 domain separator for signature verification
    bytes32 public constant SET_WALLET_TYPEHASH = keccak256("SetAgentWallet(uint256 agentId,address wallet,uint256 nonce)");

    /// @dev Events per ERC-8004
    event AgentRegistered(uint256 indexed agentId, address indexed tbaAddress);
    event AgentWalletSet(uint256 indexed agentId, address indexed wallet, bytes signature);
    event MetadataUpdated(uint256 indexed agentId, string metadataURI);
    event MetadataSet(uint256 indexed agentId, string key, string value);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _erc6551Registry) public initializer {
        __ERC721_init("AgentIdentity", "AID");
        __ERC721URIStorage_init();
        __EIP712_init("IdentityRegistry", "1");
        erc6551Registry = _erc6551Registry;
        // Shape L2 gasback registration placeholder - to be filled during deployment
        // gasbackRegister(address(this));
    }

    /// @notice Prepares encoded call data for TBA.executeCall() to register an agent
    function prepareAgentRegistration() external view returns (bytes memory) {
        return abi.encodeWithSelector(this.registerAgent.selector, msg.sender);
    }

    /// @notice Registers an agent by minting an NFT to the TBA address; must be called via TBA executeCall
    function registerAgent(address tbaAddress) external {
        require(_isValidTBA(tbaAddress), "IdentityRegistry: sender not a valid TBA");
        uint256 agentId = uint256(keccak256(abi.encodePacked(tbaAddress, block.timestamp)));
        _safeMint(tbaAddress, agentId);
        emit AgentRegistered(agentId, tbaAddress);
    }

    /// @notice Sets the agent's wallet with EIP-712/ERC-1271 signature verification
    function setAgentWallet(uint256 agentId, address wallet, bytes memory signature) external {
        require(ownerOf(agentId) == msg.sender, "IdentityRegistry: not agent owner");
        uint256 currentNonce = _nonces[agentId];
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(SET_WALLET_TYPEHASH, agentId, wallet, currentNonce)));
        address signer = ECDSAUpgradeable.recover(digest, signature);
        require(signer == wallet, "IdentityRegistry: invalid signature");
        _nonces[agentId] = currentNonce + 1;
        _agentWallets[agentId] = AgentWallet(wallet, block.timestamp);
        emit AgentWalletSet(agentId, wallet, signature);
    }

    /// @notice Updates metadata URI for an agent; owner only
    function updateMetadata(uint256 agentId, string memory metadataURI) external {
        require(ownerOf(agentId) == msg.sender, "IdentityRegistry: not agent owner");
        _setTokenURI(agentId, metadataURI);
        emit MetadataUpdated(agentId, metadataURI);
    }

    /// @notice View function to get agent wallet
    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _agentWallets[agentId].wallet;
    }
    
    /// @notice Allows the owner of an agent NFT to set the agent's metadata URI
    /// @param agentId The ID of the agent
    /// @param newAgentURI The new metadata URI for the agent
    function setAgentURI(uint256 agentId, string calldata newAgentURI) external onlyOwnerOf(agentId) {
        _setTokenURI(agentId, newAgentURI);
    }
    
    /// @notice Allows the owner of an agent NFT to unset the agent's associated wallet
    /// @param agentId The ID of the agent to modify
    function unsetAgentWallet(uint256 agentId) external onlyOwnerOf(agentId) {
        delete _agentWallets[agentId];
    }
    
    /// @notice Sets a metadata key-value pair for a given agent
    /// @dev Can only be called by the owner of the agent NFT
    /// @param agentId The ID of the agent
    /// @param key The metadata key
    /// @param value The metadata value
    function setMetadata(uint256 agentId, string calldata key, string calldata value) external onlyOwnerOf(agentId) {
        _agentMetadata[agentId][key] = value;
        emit MetadataSet(agentId, key, value);
    }
    
    /// @notice Retrieves metadata for a given agent by key
    /// @param agentId The ID of the agent
    /// @param key The metadata key
    /// @return value The metadata value associated with the key
    function getMetadata(uint256 agentId, string calldata key) external view returns (string memory value) {
        return _agentMetadata[agentId][key];
    }
    
    /// @notice Get current nonce for an agent
    function getNonce(uint256 agentId) external view returns (uint256) {
        return _nonces[agentId];
    }

    /// @dev Internal function to validate TBA via ERC-6551 registry
    function _isValidTBA(address tbaAddress) internal view returns (bool) {
        // Simplified check; in production, verify with ERC-6551 registry
        IERC6551Registry registry = IERC6551Registry(erc6551Registry);
        // Assume registry.getAccount() returns TBA details; adjust based on actual interface
        // For now, return true if address is not zero
        return tbaAddress != address(0);
    }

    /// @dev Override supportsInterface for EIP-165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Override tokenURI for ERC721URIStorage
    function tokenURI(uint256 tokenId) public view virtual override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
