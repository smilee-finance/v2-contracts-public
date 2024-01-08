// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Setup} from "./Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Setup {
    event AddStakingVault(uint256);
    event Log(uint256);

    bool internal vaultAdded;

    function setup() internal virtual override {
      deploy();
    }

    function testAddStakingVault(uint256 allocPoint) public {
        allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
        if (!vaultAdded) {
            _init(allocPoint);
            MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));

            emit AddStakingVault(vaultInfo.allocPoint);
            assert(allocPoint == vaultInfo.allocPoint);
            assert(0 == vaultInfo.accSmileePerShare);
        }
    }

    function testFirstDepositShareInVault(uint256 allocPoint, uint256 depositAmount) public {
        // PRE CONDITIONS
        skipDay(false);
        if (!vaultAdded) {
            allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
            _init(allocPoint);
        }
        uint256 initialBalance = IERC20(vault).balanceOf(alice);
        depositAmount = _between(depositAmount, 1, initialBalance);

        _stake(alice, depositAmount);

        // POST CONDITIONS
        emit Log(initialBalance - depositAmount);
        assert(IERC20(vault).balanceOf(alice) == initialBalance - depositAmount);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        assert(block.timestamp == vaultInfo.lastRewardTimestamp);
    }

    function testMultipleDeposit(uint256 allocPoint, uint256 aliceDepositAmount, uint256 bobDepositAmount) public {
        skipDay(false);
        if (!vaultAdded) {
            allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
            _init(allocPoint);
        }

        // First deposit by Alice
        uint256 aliceInitialBalance = IERC20(vault).balanceOf(alice);
        aliceDepositAmount = _between(aliceDepositAmount, 1, aliceInitialBalance);

        _stake(alice, aliceDepositAmount);

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs)); // aliceDepositAmount
        skipDay(false);
        MasterChefSmilee.VaultInfo memory vaultInfoPreDeposit = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfoPreDeposit.lastRewardTimestamp)).unwrap();

        // Second deposit on same vault (shareSupply > 0)
        uint256 bobInitialBalance = IERC20(vault).balanceOf(bob);
        bobDepositAmount = _between(bobDepositAmount, 1, bobInitialBalance);

        _stake(bob, bobDepositAmount);

        assert(bobDepositAmount + aliceDepositAmount <= mcs.totalStaked()); // Total stake within all vaults

        MasterChefSmilee.VaultInfo memory vaultInfoAfterDeposit = mcs.getVaultInfo(address(vault));
        /**
            smileePerSec = 1
            allocPoint = totalAllocPoint -> only one stake vault
            expectedRewardSupply = multiplier * smileePerSec * allocPoint / totalAllocPoint
         */
        uint256 expectedRewardSupply = ud(multiplier).unwrap();
        assert (expectedRewardSupply <= ud(mcs.rewardSupply()).unwrap());

        // accSmileePerShare = 0
        uint256 expectedAccSmileePerSec = ud(expectedRewardSupply).div(convert(shareSupply)).unwrap();
        assert (expectedAccSmileePerSec <= vaultInfoAfterDeposit.accSmileePerShare);
    }

    function testPendingRewardAfterTimes(uint256 allocPoint) public {
        skipDay(false);
        if (!vaultAdded) {
            allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
            _init(allocPoint);
        }

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs));

        skipDay(false);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);
        emit Log(amount);
        emit Log(rewardDebt);
        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = totalAllocPoint
            pendingReward = amount * multiplier / totalAllocPoint - rewardDebt
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedPendingReward = ud(amount)
            .mul(ud(multiplier))
            .div(convert(shareSupply))
            .sub(ud(rewardDebt))
            .unwrap();
        (uint256 pendingRewardToken, , ) = mcs.pendingTokens(address(vault), alice);
        emit Log(expectedPendingReward);
        emit Log(pendingRewardToken);
        assert(expectedPendingReward <= pendingRewardToken);
    }

    function testHarvestRewardAfterTimes(uint256 allocPoint) public {
        skipDay(false);
        if (!vaultAdded) {
            allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
            _init(allocPoint);
        }

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs));

        skipDay(false);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);

        hevm.prank(alice);
        mcs.harvest(address(vault));
        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = totalAllocPoint
            pendingReward = amount * multiplier / totalAllocPoint -rewardDebt
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedReward = ud(amount).mul(ud(multiplier)).div(convert(shareSupply)).sub(ud(rewardDebt)).unwrap();

        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), alice);

        assert(expectedReward <= rewardCollect);
    }

    function testWithdrawRewardAfterTimes(uint256 allocPoint) public {
        skipDay(false);
        if (!vaultAdded) {
            allocPoint = _between(allocPoint, 1, type(uint256).max - 1);
            _init(allocPoint);
        }

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs));
        uint256 aliceInitialBalance = IERC20(vault).balanceOf(alice);

        skipDay(false);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);

        hevm.prank(alice);
        mcs.withdraw(address(vault), convert(ud(amount)));
        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = totalAllocPoint
            pendingReward = amount * multiplier / totalAllocPoint - rewardDebt
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedReward = ud(amount).mul(ud(multiplier)).div(convert(shareSupply)).sub(ud(rewardDebt)).unwrap();

        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), alice);

        uint256 expectedAliceFinalShareBalance = convert(ud(amount).add(convert(aliceInitialBalance)));
        emit Log(expectedAliceFinalShareBalance);
        emit Log(IERC20(vault).balanceOf(alice));
        assert(expectedAliceFinalShareBalance == IERC20(vault).balanceOf(alice)); // assert share balance after withdraw

        emit Log(expectedReward);
        emit Log(rewardCollect);
        assert(expectedReward <= rewardCollect);
    }

    /* --- FUNCTIONS --- */

    function _init(uint256 allocPoint) internal {
        mcs.add(address(vault), allocPoint, rewarder);
        vaultAdded = true;
    }

    function _stake(address user, uint256 amount) internal {
        hevm.prank(user);
        vault.approve(address(mcs), amount);
        hevm.prank(user);
        mcs.deposit(address(vault), amount);
    }
}
