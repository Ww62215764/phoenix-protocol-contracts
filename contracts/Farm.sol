// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./USDS.sol";
import "./Vault.sol";

contract Farm is AccessControl, ReentrancyGuard {
    USDS public immutable usds;
    Vault public immutable vault;
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 stakeStartTime;
        uint256 loyaltyPoints;
        uint16 rewardMultiplier;
    }
    mapping(address => UserInfo) public users;
    
    mapping(address => address) public referrers; // referee => referrer

    struct CommissionInfo {
        uint256 pending;
        uint8 releaseStage;
        uint256 nextReleaseTime;
    }
    mapping(address => CommissionInfo) public commissions;

    struct PendingCommission {
        address referee;
        uint256 commissionAmount;
        uint256 validationTime;
    }
    mapping(address => PendingCommission[]) public pendingCommissions;

    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public totalLocked;
    uint256 public constant MIN_LOCK_AMOUNT = 10 * 1e18;
    uint256 public constant MAX_PENDING_COMMISSIONS = 100;
    uint256 public minLockPeriod = 5 days;
    uint256 public maxLockPeriod = 10 days;

    uint256 public constant APY_STAGE1_TVL = 20_000_000 * 1e18;
    uint256 public constant APY_STAGE2_TVL = 100_000_000 * 1e18;
    uint256 public constant APY_STAGE3_TVL = 250_000_000 * 1e18;

    uint256 public constant APY_STAGE1 = 50;
    uint256 public constant APY_STAGE2 = 35;
    uint256 public constant APY_STAGE3 = 25;
    uint256 public constant APY_FINAL = 15;

    event Minted(address indexed user, uint256 amount);
    event Locked(address indexed user, uint256 amount, uint256 period);
    event Claimed(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 fee);
    event Referral(address indexed ref, address indexed referee, uint256 amount);
    event APYStageChanged(uint8 indexed stage, uint256 newAPY);
    event ReferralCommissionReleased(address indexed referrer, uint256 amount, uint8 stage);
    event PendingCommissionProcessed(address indexed referrer, address indexed referee, uint256 amount);

    constructor(address _usds, address _vault, address admin) {
        usds = USDS(_usds);
        vault = Vault(_vault);
        _grantRole(ADMIN_ROLE, admin);
        lastRewardTime = block.timestamp;
    }

    function getCurrentAPY() public view returns (uint256) {
        uint256 tvl = vault.usdt().balanceOf(address(vault));
        if (tvl < APY_STAGE1_TVL) return APY_STAGE1;
        if (tvl < APY_STAGE2_TVL) return APY_STAGE2;
        if (tvl < APY_STAGE3_TVL) return APY_STAGE3;
        return APY_FINAL;
    }

    function earned(address account) public view returns (uint256) {
        UserInfo storage user = users[account];
        if (user.amount == 0) return 0;
        uint256 currentAccRewardPerShare = _getUpdatedAccRewardPerShare();
        uint256 baseReward = (user.amount * currentAccRewardPerShare) / 1e12;
        return (baseReward * user.rewardMultiplier / 10000) - user.rewardDebt;
    }

    function mint(uint256 amount, address referrer) external nonReentrant {
        if (referrer != address(0) && referrers[msg.sender] == address(0) && referrer != msg.sender) {
            referrers[msg.sender] = referrer;
        }
        vault.depositFor(msg.sender, amount);
        usds.mint(msg.sender, amount);
        emit Minted(msg.sender, amount);
    }

    function lock(uint256 amount, uint256 period) external nonReentrant {
        require(amount >= MIN_LOCK_AMOUNT, "Farm: Lock amount too small");
        require(period >= minLockPeriod && period <= maxLockPeriod, "Invalid lock period");
        
        _updatePoolAndUser(msg.sender);

        usds.transferFrom(msg.sender, address(this), amount);
        usds.burn(address(this), amount);

        UserInfo storage user = users[msg.sender];
        user.amount += amount;
        if (user.stakeStartTime == 0) {
            user.stakeStartTime = block.timestamp;
        }
        
        uint16 newMultiplier = _getMultiplierForPeriod(period);
        if (newMultiplier > user.rewardMultiplier) {
            user.rewardMultiplier = newMultiplier;
        }
        
        user.rewardDebt = (user.amount * accRewardPerShare * user.rewardMultiplier) / 10000 / 1e12;
        totalLocked += amount;
        
        _handleReferral(msg.sender, amount);
        
        emit Locked(msg.sender, amount, period);
    }
    
    function withdraw(uint256 amount) external nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.amount >= amount, "Insufficient locked balance");
        require(block.timestamp >= user.stakeStartTime + minLockPeriod, "Funds are still locked");

        _updatePoolAndUser(msg.sender);

        uint256 fee = _calculateWithdrawFee(user.stakeStartTime, amount);
        uint256 amountToReturn = amount - fee;

        user.amount -= amount;
        
        if (user.amount == 0) {
            user.stakeStartTime = 0;
            user.rewardMultiplier = 0;
            user.loyaltyPoints = 0;
        }
        
        user.rewardDebt = (user.amount * accRewardPerShare * user.rewardMultiplier) / 10000 / 1e12;
        totalLocked -= amount;

        vault.withdrawTo(msg.sender, amountToReturn);
        if (fee > 0) {
            vault.addFee(fee);
        }
        emit Withdrawn(msg.sender, amount, fee);
    }

    function claimRewards() external nonReentrant {
        _updatePoolAndUser(msg.sender);
    }

    function _updatePoolAndUser(address account) internal {
        uint256 currentAccRewardPerShare = _getUpdatedAccRewardPerShare();
        UserInfo storage user = users[account];
        if (user.amount > 0) {
            user.loyaltyPoints += user.amount * (block.timestamp - lastRewardTime);
            uint256 pending = earned(account);
            if (pending > 0) {
                usds.mint(account, pending);
                emit Claimed(account, pending);
            }
        }
        accRewardPerShare = currentAccRewardPerShare;
        lastRewardTime = block.timestamp;
        user.rewardDebt = (user.amount * accRewardPerShare * user.rewardMultiplier) / 10000 / 1e12;
    }
    
    function _getUpdatedAccRewardPerShare() internal view returns (uint256) {
        if (block.timestamp <= lastRewardTime || totalLocked == 0) return accRewardPerShare;
        uint256 apy = getCurrentAPY();
        uint256 rewardPerSecond = (totalLocked * apy / 100) / 365 days;
        uint256 timeDelta = block.timestamp - lastRewardTime;
        uint256 reward = timeDelta * rewardPerSecond;
        return accRewardPerShare + (reward * 1e12) / totalLocked;
    }

    function _handleReferral(address referee, uint256 amount) internal {
        address referrer = referrers[referee];
        if (referrer != address(0) && users[referrer].amount > 0) {
            require(pendingCommissions[referrer].length < MAX_PENDING_COMMISSIONS, "Farm: Referrer's pending queue is full");
            uint256 commissionAmount = (amount * 20) / 100;
            pendingCommissions[referrer].push(PendingCommission({
                referee: referee,
                commissionAmount: commissionAmount,
                validationTime: block.timestamp + 3 days
            }));
            emit Referral(referrer, referee, commissionAmount);
        }
    }
    
    function processMyCommissions() external nonReentrant {
        PendingCommission[] storage pendings = pendingCommissions[msg.sender];
        for (uint i = 0; i < pendings.length; ) {
            if (pendings[i].validationTime != 0 && block.timestamp >= pendings[i].validationTime) {
                PendingCommission memory p = pendings[i];
                pendings[i] = pendings[pendings.length - 1];
                pendings.pop();

                if (users[p.referee].amount > 0) {
                    uint256 totalReward = p.commissionAmount;
                    usds.mint(msg.sender, totalReward * 30 / 100);
                    
                    CommissionInfo storage refInfo = commissions[msg.sender];
                    refInfo.pending += totalReward * 70 / 100;
                    if (refInfo.releaseStage == 0) {
                        refInfo.releaseStage = 1;
                        refInfo.nextReleaseTime = block.timestamp + 30 days;
                    }
                    emit PendingCommissionProcessed(msg.sender, p.referee, totalReward);
                }
            } else {
                i++;
            }
        }
    }
    
    function releaseStagedCommission() external nonReentrant {
        CommissionInfo storage info = commissions[msg.sender];
        require(info.pending > 0, "No pending commission");
        require(block.timestamp >= info.nextReleaseTime, "Release period not reached");
        require(info.releaseStage < 3, "All stages released");

        uint256 amountToRelease;
        if (info.releaseStage == 1) {
            amountToRelease = info.pending * 30 / 70;
            info.releaseStage = 2;
            info.nextReleaseTime = block.timestamp + 30 days;
        } else if (info.releaseStage == 2) {
            amountToRelease = info.pending;
            info.releaseStage = 3;
        }
        
        if (amountToRelease > 0) {
            info.pending -= amountToRelease;
            usds.mint(msg.sender, amountToRelease);
            emit ReferralCommissionReleased(msg.sender, amountToRelease, info.releaseStage);
        }
    }

    function _getMultiplierForPeriod(uint256 period) internal pure returns (uint16) {
        if (period >= 10 days) return 11000;
        if (period >= 7 days) return 10500;
        return 10000;
    }

    function _calculateWithdrawFee(uint256 startTime, uint256 amount) internal view returns (uint256) {
        uint256 timeLocked = block.timestamp - startTime;
        if (timeLocked < 15 days) return (amount * 10) / 100;
        if (timeLocked < 30 days) return (amount * 5) / 100;
        return 0;
    }

    function announceAPYStage(uint8 stage, uint256 newAPY) external onlyRole(ADMIN_ROLE) {
        emit APYStageChanged(stage, newAPY);
    }
}
