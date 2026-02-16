// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ValidationRegistry is OwnableUpgradeable {
    /// @dev Struct for validation request
    struct ValidationRequest {
        address validatorAddress;
        uint256 agentId;
        string requestURI;
        bytes32 requestHash;
        uint8 response; // 0 = pending, 1 = approved, 2 = rejected
        string responseURI;
        bytes32 responseHash;
        string tag;
        uint64 timestamp;
    }

    /// @dev Mapping from requestHash to ValidationRequest
    mapping(bytes32 => ValidationRequest) private _requests;
    
    /// @dev Registered validators mapping
    mapping(address => bool) public registeredValidators;

    /// @dev Events per ERC-8004
    event ValidationRequested(bytes32 indexed requestHash, address indexed validatorAddress, uint256 indexed agentId, string requestURI);
    event ValidationResponded(bytes32 indexed requestHash, uint8 response, string responseURI, string tag);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        // Shape L2 gasback registration placeholder
    }

    /// @notice Submit a validation request
    function validationRequest(address validatorAddress, uint256 agentId, string memory requestURI, bytes32 requestHash) external {
        require(_requests[requestHash].validatorAddress == address(0), "ValidationRegistry: request already exists");
        _requests[requestHash] = ValidationRequest({
            validatorAddress: validatorAddress,
            agentId: agentId,
            requestURI: requestURI,
            requestHash: requestHash,
            response: 0,
            responseURI: "",
            responseHash: bytes32(0),
            tag: "",
            timestamp: uint64(block.timestamp)
        });
        emit ValidationRequested(requestHash, validatorAddress, agentId, requestURI);
    }

    /// @notice Submit a validation response
    function validationResponse(bytes32 requestHash, uint8 response, string memory responseURI, bytes32 responseHash, string memory tag) external {
        require(registeredValidators[msg.sender], "ValidationRegistry: not a validator");
        ValidationRequest storage req = _requests[requestHash];
        require(req.validatorAddress == msg.sender, "ValidationRegistry: not the validator");
        require(req.response == 0, "ValidationRegistry: already responded");
        req.response = response;
        req.responseURI = responseURI;
        req.responseHash = responseHash;
        req.tag = tag;
        emit ValidationResponded(requestHash, response, responseURI, tag);
    }

    /// @notice Get validation status
    function getValidationStatus(bytes32 requestHash) external view returns (ValidationRequest memory) {
        return _requests[requestHash];
    }

    /// @notice Get summary for an agent
    function getSummary(uint256 agentId, address[] memory validatorAddresses, string memory tag) external view returns (uint256 approved, uint256 total) {
        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            // In practice, need to iterate over requests; this is simplified
            // For production, use indexed events or additional mappings
        }
    }

    /// @dev EIP-165 support
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
