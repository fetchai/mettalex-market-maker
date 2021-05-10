// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IMetalX.sol";

interface IMTLXMigrator {
    // Perform LP token migration from legacy UniswapV2 to Mettalex AMM.
    // Take the current LP token address and return the new LP token address from Mettalex AMM.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // Mettalex must mint EXACTLY the same amount of mettalex AMM LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

// Amplify is MTLX distibutor.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once MTLX is sufficiently
// distributed and the community can show to govern itself.

contract Reward is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        bool enrolled;
        //
        // We do some fancy math here. Basically, any point in time, the amount of MTLXs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMTLXPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMTLXPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Array which stores addresses of all the participants. Doesn't duplicate the address.
    address[] public userAddresses;

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. MTLXs to distribute per block.
        uint256 lastRewardBlock; // Last block number that MTLXs distribution occurs.
        uint256 accMTLXPerShare; // Accumulated MTLXs per share, times 1e12. See below.
    }

    // The MTLX TOKEN!
    IMetalX public MTLX;
    // Dev address.
    address public devaddr;
    // Block number when bonus MTLX period ends.
    uint256 public bonusEndBlock;
    // MTLX tokens distributed per block.
    uint256 public MTLXPerBlock;
    // Bonus muliplier for early MTLX farmers.
    uint256 public constant BONUS_MULTIPLIER = 2;

    uint256 public constant REWARD_FACTOR = 10;

    // Exit fee in percentage, scaled by e18. e.g. if exit fee is 2%, then exitFeeFactor should be 2e18
    uint256 public exitFeeFactor;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMTLXMigrator public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when MTLX mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IMetalX _MTLX,
        address _devaddr,
        uint256 _MTLXPerBlock,
        uint256 _exitFeeFactor,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) {
        MTLX = _MTLX;
        devaddr = _devaddr;
        MTLXPerBlock = _MTLXPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        exitFeeFactor = _exitFeeFactor;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function userAddressesLength() external view returns (uint256) {
        return userAddresses.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accMTLXPerShare: 0
            })
        );
    }

    // Update the given pool's MTLX allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMTLXMigrator _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // View function to see pending MTLXs on frontend.
    function pendingMTLX(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMTLXPerShare = pool.accMTLXPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 MTLXReward =
                multiplier.mul(MTLXPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accMTLXPerShare = accMTLXPerShare.add(
                MTLXReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accMTLXPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 MTLXReward =
            multiplier.mul(MTLXPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        MTLX.transfer(devaddr, MTLXReward.div(REWARD_FACTOR));
        pool.accMTLXPerShare = pool.accMTLXPerShare.add(
            MTLXReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Amplify for MTLX allocation.
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.enrolled == false) {
            userAddresses.push(msg.sender);
            user.enrolled = true;
        }
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accMTLXPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                safeMTLXTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMTLXPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Amplify.
    function withdraw(uint256 _pid, uint256 _amount) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accMTLXPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            safeMTLXTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 exitFee = _amount.mul(exitFeeFactor).div(100).div(1e18);
            pool.lpToken.safeTransfer(
                address(msg.sender),
                _amount.sub(exitFee)
            );
            pool.lpToken.safeTransfer(devaddr, exitFee);
        }
        user.rewardDebt = user.amount.mul(pool.accMTLXPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe MTLX transfer function, just in case if rounding error causes pool to not have enough MTLXs.
    function safeMTLXTransfer(address _to, uint256 _amount) internal {
        uint256 MTLXBal = MTLX.balanceOf(address(this));
        if (_amount > MTLXBal) {
            MTLX.transfer(_to, MTLXBal);
        } else {
            MTLX.transfer(_to, _amount);
        }
    }

    // ADMIN METHODS

    // Update dev address by the admin.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    function pauseDistribution() public onlyOwner {
        _pause();
    }

    function resumeDistribution() public onlyOwner {
        _unpause();
    }

    function setMTLXRewardPerBlock(uint256 _newReward) public onlyOwner {
        massUpdatePools();
        MTLXPerBlock = _newReward;
    }

    function setExitFeeFactor(uint256 _newExitFeeFactor) public onlyOwner {
        exitFeeFactor = _newExitFeeFactor;
    }

    function withdrawAdminMTLX(uint256 amount) public onlyOwner {
        MTLX.transfer(msg.sender, amount);
    }
}