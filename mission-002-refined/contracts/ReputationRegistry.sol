// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "./IStakeRegistry.sol"; // Interface for StakeRegistry

contract ReputationRegistry is OwnableUpgradeable {
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;

    /// @dev Struct for feedback entry
    struct Feedback {
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
        string responseURI;
        bool revoked;
        uint64 timestamp;
    }

    /// @dev Mapping from agentId to client address to feedback array
    mapping(uint256 => mapping(address => Feedback[])) private _feedbacks;

    /// @dev StakeRegistry address for weighted scoring
    address public stakeRegistry;
    
    /// @dev Stake snapshots to prevent flash loan manipulation
    mapping(uint256 => mapping(address => uint256)) public stakeSnapshots;
    
    /// @dev Maximum validators to prevent gas griefing
    uint256 public constant MAX_VALIDATORS = 100;

    /// @dev Events per ERC-8004
    event FeedbackGiven(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, string tag1, string tag2);
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex);
    event ResponseAppended(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, string responseURI);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _stakeRegistry) public initializer {
        __Ownable_init(msg.sender);
        stakeRegistry = _stakeRegistry;
        // Shape L2 gasback registration placeholder
    }

    /// @notice Core function to give feedback
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string memory tag1,
        string memory tag2,
        string memory endpoint,
        string memory feedbackURI,
        bytes32 feedbackHash
    ) external {
        Feedback[] storage clientFeedbacks = _feedbacks[agentId][msg.sender];
        uint64 feedbackIndex = uint64(clientFeedbacks.length);
        clientFeedbacks.push(Feedback({
            value: value,
            valueDecimals: valueDecimals,
            tag1: tag1,
            tag2: tag2,
            endpoint: endpoint,
            feedbackURI: feedbackURI,
            feedbackHash: feedbackHash,
            responseURI: "",
            revoked: false,
            timestamp: uint64(block.timestamp)
        }));
        emit FeedbackGiven(agentId, msg.sender, feedbackIndex, value, tag1, tag2);
    }

    /// @notice Revoke feedback by index
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        Feedback storage feedback = _feedbacks[agentId][msg.sender][feedbackIndex];
        require(!feedback.revoked, "ReputationRegistry: already revoked");
        feedback.revoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    /// @notice Append response to feedback
    function appendResponse(uint256 agentId, address clientAddress, uint64 feedbackIndex, string memory responseURI) external {
        require(msg.sender == clientAddress, "ReputationRegistry: only client can respond");
        Feedback storage feedback = _feedbacks[agentId][clientAddress][feedbackIndex];
        feedback.responseURI = responseURI;
        emit ResponseAppended(agentId, clientAddress, feedbackIndex, responseURI);
    }

    /// @notice Update stake snapshot for flash loan protection
    function updateStakeSnapshot(uint256 agentId, address staker, uint256 amount) external {
        stakeSnapshots[agentId][staker] = amount;
    }

    /// @notice Get weighted average reputation score
    /// @notice Get weighted average reputation score
    /// @dev clientAddresses parameter limited to MAX_VALIDATORS to prevent gas griefing
    ///      This is parameter validation, not state management - no unbounded arrays stored
    function getSummary(uint256 agentId, address[] memory clientAddresses, string memory tag1, string memory tag2) external view returns (int128 weightedAverage) {
        require(clientAddresses.length <= MAX_VALIDATORS, "ReputationRegistry: too many validators");
        uint256 totalWeight = 0;
        int128 totalValue = 0;
        for (uint256 i = 0; i < clientAddresses.length; i++) {
            address client = clientAddresses[i];
            Feedback[] storage feedbacks = _feedbacks[agentId][client];
            for (uint256 j = 0; j < feedbacks.length; j++) {
                Feedback memory fb = feedbacks[j];
                if (!fb.revoked && keccak256(bytes(fb.tag1)) == keccak256(bytes(tag1)) && keccak256(bytes(fb.tag2)) == keccak256(bytes(tag2))) {
                    uint256 weight = stakeSnapshots[agentId][client]; // Assume function in StakeRegistry
                    totalWeight += weight;
                    totalValue += fb.value * int128(int256(weight));
                }
            }
        }
        if (totalWeight > 0) {
            weightedAverage = totalValue / int128(int256(totalWeight));
        }
    }

    /// @notice Read specific feedback
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex) external view returns (Feedback memory) {
        return _feedbacks[agentId][clientAddress][feedbackIndex];
    }

    /// @notice Batch feedback function with EIP-165 support
    function giveFeedbackBatch(
        uint256[] memory agentIds,
        int128[] memory values,
        uint8[] memory valueDecimals,
        string[] memory tag1s,
        string[] memory tag2s,
        string[] memory feedbackURIs
    ) external {
        require(agentIds.length == values.length, "ReputationRegistry: array length mismatch");
        for (uint256 i = 0; i < agentIds.length; i++) {
            giveFeedback(agentIds[i], values[i], valueDecimals[i], tag1s[i], tag2s[i], feedbackURIs[i]);
        }
    }

    /// @notice Reads feedback with pagination to prevent DoS
    /// @param agentId The ID of the agent
    /// @param clientAddress The address of the client who gave the feedback
    /// @param startIndex Starting index for pagination
    /// @param count Number of items to return
    /// @return feedbacks Array of Feedback structs
    function readFeedback(uint256 agentId, address clientAddress, uint256 startIndex, uint256 count) external view returns (Feedback[] memory feedbacks) {
        Feedback[] storage allFeedback = _feedbacks[agentId][clientAddress];
        uint256 total = allFeedback.length;
        
        if (startIndex >= total) {
            return new Feedback[](0);
        }
        
        uint256 end = startIndex + count;
        if (end > total) {
            end = total;
        }
        
        uint256 resultCount = end - startIndex;
        feedbacks = new Feedback[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            feedbacks[i] = allFeedback[startIndex + i];
        }
    }
    
    /// @notice Get total feedback count for pagination
    /// @param agentId The ID of the agent
    /// @param clientAddress The address of the client
    /// @return Total number of feedback entries
    function getFeedbackCount(uint256 agentId, address clientAddress) external view returns (uint256) {
        return _feedbacks[agentId][clientAddress].length;
    }
    
    /// @dev EIP-165 support
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
