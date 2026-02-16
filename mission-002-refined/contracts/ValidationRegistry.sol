// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ValidationRegistry is OwnableUpgradeable {
    /// @dev Struct for single response
    struct Response {
        uint8 code;
        string responseURI;
        bytes32 responseHash;
        string tag;
        uint64 timestamp;
    }
    
    /// @dev Struct for validation request
    struct ValidationRequest {
        address validatorAddress;
        uint256 agentId;
        string requestURI;
        bytes32 requestHash;
        Response[] responses;
        bool completed;
        uint64 timestamp;
    }

    /// @dev Mapping from requestHash to ValidationRequest
    mapping(bytes32 => ValidationRequest) private _requests;
    
    /// @dev Track request IDs for a given agent
    mapping(uint256 => bytes32[]) private _agentRequestIds;
    
    /// @dev Track request IDs for a given validator
    mapping(address => bytes32[]) private _validatorRequestIds;
    
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
        _requests[requestHash].validatorAddress = validatorAddress;
        _requests[requestHash].agentId = agentId;
        _requests[requestHash].requestURI = requestURI;
        _requests[requestHash].requestHash = requestHash;
        _requests[requestHash].completed = false;
        _requests[requestHash].timestamp = uint64(block.timestamp);
        
        _agentRequestIds[agentId].push(requestHash);
        _validatorRequestIds[validatorAddress].push(requestHash);
        
        emit ValidationRequested(requestHash, validatorAddress, agentId, requestURI);
    }

    /// @notice Append a response to a validation request (supports multiple responses)
    function appendResponse(bytes32 requestHash, uint8 response, string memory responseURI, bytes32 responseHash, string memory tag) external {
        require(registeredValidators[msg.sender], "ValidationRegistry: not a validator");
        ValidationRequest storage req = _requests[requestHash];
        require(req.validatorAddress == msg.sender, "ValidationRegistry: not the validator");
        require(!req.completed, "ValidationRegistry: request already completed");
        
        req.responses.push(Response({
            code: response,
            responseURI: responseURI,
            responseHash: responseHash,
            tag: tag,
            timestamp: uint64(block.timestamp)
        }));
        
        emit ValidationResponded(requestHash, response, responseURI, tag);
    }
    
    /// @notice Mark a validation request as completed
    function completeValidation(bytes32 requestHash) external {
        ValidationRequest storage req = _requests[requestHash];
        require(req.validatorAddress == msg.sender, "ValidationRegistry: not the validator");
        req.completed = true;
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

    /// @notice Get validation requests for an agent with pagination
    /// @param agentId The ID of the agent
    /// @param startIndex Starting index for pagination
    /// @param count Number of items to return
    /// @return requests Array of validation requests
    function getAgentValidations(uint256 agentId, uint256 startIndex, uint256 count) external view returns (ValidationRequest[] memory requests) {
        bytes32[] storage requestHashes = _agentRequestIds[agentId];
        uint256 total = requestHashes.length;
        
        if (startIndex >= total) {
            return new ValidationRequest[](0);
        }
        
        uint256 end = startIndex + count;
        if (end > total) {
            end = total;
        }
        
        uint256 resultCount = end - startIndex;
        requests = new ValidationRequest[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            requests[i] = _requests[requestHashes[startIndex + i]];
        }
    }
    
    /// @notice Get total validation count for an agent
    /// @param agentId The ID of the agent
    /// @return Total number of validation requests
    function getAgentValidationCount(uint256 agentId) external view returns (uint256) {
        return _agentRequestIds[agentId].length;
    }
    
    /// @notice Get validation requests for a validator with pagination
    /// @param validatorAddress The address of the validator
    /// @param startIndex Starting index for pagination
    /// @param count Number of items to return
    /// @return requests Array of validation requests
    function getValidatorRequests(address validatorAddress, uint256 startIndex, uint256 count) external view returns (ValidationRequest[] memory requests) {
        bytes32[] storage requestHashes = _validatorRequestIds[validatorAddress];
        uint256 total = requestHashes.length;
        
        if (startIndex >= total) {
            return new ValidationRequest[](0);
        }
        
        uint256 end = startIndex + count;
        if (end > total) {
            end = total;
        }
        
        uint256 resultCount = end - startIndex;
        requests = new ValidationRequest[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            requests[i] = _requests[requestHashes[startIndex + i]];
        }
    }
    
    /// @notice Get total validation count for a validator
    /// @param validatorAddress The address of the validator
    /// @return Total number of validation requests
    function getValidatorRequestCount(address validatorAddress) external view returns (uint256) {
        return _validatorRequestIds[validatorAddress].length;
    }
    
    /// @dev EIP-165 support
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
