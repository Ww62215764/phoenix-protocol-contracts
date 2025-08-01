// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vault is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable usdt;
    address public farm;
    address public oracleManager;
    uint256 public accumulatedFees;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant HEALTH_CHECK_TIMEOUT = 1 hours;

    uint256 public pendingWithdrawalAmount;
    address public pendingWithdrawalTo;
    uint256 public withdrawalUnlockTime;
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    uint256 public lastHealthCheck;

    event FarmAddressSet(address indexed farm);
    event OracleManagerSet(address indexed oracleManager);
    event WithdrawalProposed(address indexed to, uint256 amount, uint256 unlockTime);
    event WithdrawalExecuted(address indexed to, uint256 amount);
    event FeesClaimed(address indexed to, uint256 amount);
    event TVLChanged(uint256 tvl);

    constructor(address _usdt, address admin) {
        usdt = IERC20(_usdt);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        lastHealthCheck = block.timestamp;
    }

    function setFarmAddress(address _farm) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(farm == address(0), "Vault: Farm address already set");
        require(_farm != address(0), "Vault: Invalid farm address");
        farm = _farm;
        emit FarmAddressSet(_farm);
    }
    
    function setOracleManager(address _oracleManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oracleManager == address(0), "Vault: Oracle Manager already set");
        require(_oracleManager != address(0), "Vault: Invalid Oracle Manager address");
        oracleManager = _oracleManager;
        emit OracleManagerSet(_oracleManager);
    }

    function depositFor(address user, uint256 amount) external nonReentrant whenNotPaused {
        require(block.timestamp - lastHealthCheck < HEALTH_CHECK_TIMEOUT, "Vault: Oracle system offline");
        require(msg.sender == farm, "Vault: Caller is not the farm");
        usdt.safeTransferFrom(user, address(this), amount);
        emit TVLChanged(usdt.balanceOf(address(this)));
    }

    function withdrawTo(address user, uint256 amount) external nonReentrant whenNotPaused {
        require(block.timestamp - lastHealthCheck < HEALTH_CHECK_TIMEOUT, "Vault: Oracle system offline");
        require(msg.sender == farm, "Vault: Caller is not the farm");
        usdt.safeTransfer(user, amount);
        emit TVLChanged(usdt.balanceOf(address(this)));
    }

    function addFee(uint256 amount) external {
        require(msg.sender == farm, "Vault: Caller is not the farm");
        accumulatedFees += amount;
    }

    function claimFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 feesToClaim = accumulatedFees;
        accumulatedFees = 0;
        usdt.safeTransfer(to, feesToClaim);
        emit FeesClaimed(to, feesToClaim);
    }

    function proposeWithdrawal(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Vault: Cannot withdraw to zero address");
        require(usdt.balanceOf(address(this)) >= amount, "Vault: Insufficient funds for proposal");
        pendingWithdrawalAmount = amount;
        pendingWithdrawalTo = to;
        withdrawalUnlockTime = block.timestamp + TIMELOCK_DELAY;
        emit WithdrawalProposed(to, amount, withdrawalUnlockTime);
    }

    function executeWithdrawal() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(block.timestamp >= withdrawalUnlockTime, "Vault: Timelock has not expired");
        require(pendingWithdrawalAmount > 0, "Vault: No pending withdrawal to execute");
        
        uint256 amount = pendingWithdrawalAmount;
        address to = pendingWithdrawalTo;
        
        pendingWithdrawalAmount = 0;
        pendingWithdrawalTo = address(0);
        withdrawalUnlockTime = 0;

        usdt.safeTransfer(to, amount);
        emit WithdrawalExecuted(to, amount);
        emit TVLChanged(usdt.balanceOf(address(this)));
    }

    function heartbeat() external {
        require(msg.sender == oracleManager, "Vault: Only Oracle Manager can send heartbeat");
        lastHealthCheck = block.timestamp;
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
