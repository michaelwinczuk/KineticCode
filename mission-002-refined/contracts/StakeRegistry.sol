// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract StakeRegistry is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Struct for stake entry
    struct Stake {
        uint256 amount;
        uint256 lockUntil;
        uint256 withdrawRequestTime;
        bool slashed;
    }

    /// @dev Mapping from agentId to staker address to Stake
    mapping(uint256 => mapping(address => Stake)) private _stakes;

    /// @dev ERC20 token for staking
    IERC20Upgradeable public stakingToken;

    /// @dev Constants for timing
    uint256 public constant LOCK_DURATION = 7 days;
    uint256 public constant WITHDRAW_COOLDOWN = 2 days;

    /// @dev Events
    event Staked(uint256 indexed agentId, address indexed staker, uint256 amount);
    event WithdrawRequested(uint256 indexed agentId, address indexed staker);
    event Withdrawn(uint256 indexed agentId, address indexed staker, uint256 amount);
    event Slashed(uint256 indexed agentId, address indexed staker, uint256 amount, string reason);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _stakingToken) public initializer {
        __Ownable_init(msg.sender);
        stakingToken = IERC20Upgradeable(_stakingToken);
        // Shape L2 gasback registration placeholder
    }

    /// @notice Stake tokens for an agent
    function stake(uint256 amount, uint256 agentId) external {
        require(amount > 0, "StakeRegistry: amount must be > 0");
        Stake storage s = _stakes[agentId][msg.sender];
        s.amount += amount;
        s.lockUntil = block.timestamp + LOCK_DURATION;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(agentId, msg.sender, amount);
    }

    /// @notice Request withdrawal; initiates cooldown
    function requestWithdraw(uint256 agentId) external {
        Stake storage s = _stakes[agentId][msg.sender];
        require(s.amount > 0, "StakeRegistry: no stake");
        require(block.timestamp >= s.lockUntil, "StakeRegistry: still locked");
        s.withdrawRequestTime = block.timestamp;
        emit WithdrawRequested(agentId, msg.sender);
    }

    /// @notice Withdraw after cooldown
    function withdraw(uint256 agentId) external nonReentrant {
        Stake storage s = _stakes[agentId][msg.sender];
        require(s.amount > 0, "StakeRegistry: no stake");
        require(s.withdrawRequestTime > 0, "StakeRegistry: no withdraw request");
        require(block.timestamp >= s.withdrawRequestTime + WITHDRAW_COOLDOWN, "StakeRegistry: cooldown not met");
        require(!s.slashed, "StakeRegistry: slashed");
        uint256 amount = s.amount;
        s.amount = 0;
        s.withdrawRequestTime = 0;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(agentId, msg.sender, amount);
    }

    /// @notice Slash stake (governance action)
    function slash(uint256 agentId, address staker, uint256 amount, string memory reason) external onlyOwner {
        Stake storage s = _stakes[agentId][staker];
        require(s.amount >= amount, "StakeRegistry: insufficient stake");
        s.amount -= amount;
        s.slashed = true;
        s.lockUntil = 0;
        s.withdrawRequestTime = 0;
        // Burn or transfer slashed tokens as per governance
        stakingToken.safeTransfer(owner(), amount); // Example: transfer to owner
        emit Slashed(agentId, staker, amount, reason);
    }

    /// @notice Get lock until timestamp
    function getStakeLockUntil(uint256 agentId, address staker) external view returns (uint256) {
        return _stakes[agentId][staker].lockUntil;
    }

    /// @notice Get withdrawable amount
    function getWithdrawableAmount(uint256 agentId, address staker) external view returns (uint256) {
        Stake storage s = _stakes[agentId][staker];
        if (s.slashed || s.amount == 0) return 0;
        if (s.withdrawRequestTime > 0 && block.timestamp >= s.withdrawRequestTime + WITHDRAW_COOLDOWN) {
            return s.amount;
        }
        return 0;
    }

    /// @dev EIP-165 support
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
