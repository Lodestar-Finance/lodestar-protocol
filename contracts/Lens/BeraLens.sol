//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../CTokenInterfaces.sol';

interface StakingRewardsInterface {
    struct StakingInfo {
        uint256 lodeAmount;
        uint256 stLODEAmount;
        uint256 startTime;
        uint256 lockTime;
        uint256 relockStLODEAmount;
        uint256 nextStakeId;
        uint256 totalEsLODEStakedByUser;
        uint256 threeMonthRelockCount;
        uint256 sixMonthRelockCount;
    }

    function stakers(address user) external view returns (StakingInfo memory);
}

interface VotingPowerInterface {
    function delegates(address account) external view returns (address);
    function getCurrentWeek() external view returns (uint);
    function lastVotedWeek(address user) external view returns (uint);
    function previouslyVoted(address user) external view returns (bool);
}

contract BeraLens {
    IERC20 TEST_URSA = IERC20(0x8b2cB9F008210E84Db513c15743a1DE8064F83f3);
    IERC20 TEST_HONEY = IERC20(0xC698f8Ac0205Dc55C6a19Bc4f2F800ff32c5ECBD);
    IERC20 TEST_WBERA = IERC20(0x767230A157D9A419d1bEa97E0e37f9d2668F6b08);

    CTokenInterface URSA_MARKET = CTokenInterface(0xdDa78f48aDD4f9fC945E612f1d884Bf359f01e1A);
    CTokenInterface HONEY_MARKET = CTokenInterface(0xf192F5deC14461c0AC77b2551822F52949Ee7802);
    CTokenInterface WBERA_MARKET = CTokenInterface(0x7CED14e54Abb17FAb0B23A2Dc352bCE05cA97EE9);
    CTokenInterface BERA_MARKET = CTokenInterface(0x66C7AbD8a2097A816f99B94415b8CeBEdB247B76);

    ComptrollerInterface UNITROLLER = ComptrollerInterface(0x58Da9d46998a4B1f53fE37467941872a3D1A91c4);

    StakingRewardsInterface STAKING = StakingRewardsInterface(0x45433Dc0F38F3aed1E9dB3EA4351e4cB862dbBd7);
    VotingPowerInterface VOTING = VotingPowerInterface(0x30b46Bb280cE5B6829AE7a4fC5e8D37B87A507D6);

    IERC20[] tokens = [TEST_HONEY, TEST_URSA, TEST_WBERA];
    CTokenInterface[] markets = [URSA_MARKET, HONEY_MARKET, WBERA_MARKET, BERA_MARKET];

    struct StakingInfo {
        uint256 lodeAmount;
        uint256 stLODEAmount;
        uint256 startTime;
        uint256 lockTime;
        uint256 relockStLODEAmount;
        uint256 nextStakeId;
        uint256 totalEsLODEStakedByUser;
        uint256 threeMonthRelockCount;
        uint256 sixMonthRelockCount;
    }

    function hasUserDripped(address user) public view returns (bool) {
        for (uint i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = tokens[i].balanceOf(user);
            if (tokenBalance > 0) {
                return true;
            }
        }
        return false;
    }

    function hasUserMinted(address user) public view returns (bool) {
        for (uint i = 0; i < markets.length; i++) {
            uint256 cTokenBalance = markets[i].balanceOf(user);
            if (cTokenBalance > 0) {
                return true;
            }
        }
        return false;
    }

    function hasUserBorrowed(address user) public view returns (bool) {
        for (uint i = 0; i < markets.length; i++) {
            uint256 borrowBalance = markets[i].borrowBalanceStored(user);
            if (borrowBalance > 0) {
                return true;
            }
        }
        return false;
    }

    function hasUserStakedWithoutLock(address user) public view returns (bool) {
        StakingRewardsInterface.StakingInfo memory stakingInfo = STAKING.stakers(user);
        if (stakingInfo.lodeAmount > 0 && stakingInfo.lockTime == 10) {
            return true;
        } else {
            return false;
        }
    }

    function hasUserStakedWithLock(address user) public view returns (bool) {
        StakingRewardsInterface.StakingInfo memory stakingInfo = STAKING.stakers(user);
        if (
            (stakingInfo.lodeAmount > 0 && stakingInfo.lockTime == 90 days) ||
            (stakingInfo.lodeAmount > 0 && stakingInfo.lockTime == 180 days)
        ) {
            return true;
        } else {
            return false;
        }
    }

    function hasUserDelegated(address user) public view returns (bool) {
        address delegate = VOTING.delegates(user);
        if (delegate != address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function hasUserVoted(address user) public view returns (bool) {
        bool previouslyVoted = VOTING.previouslyVoted(user);
        if (previouslyVoted) {
            return true;
        }
        uint256 currentWeek = VOTING.getCurrentWeek();
        uint256 lastVotedWeek = VOTING.lastVotedWeek(user);
        if (currentWeek == lastVotedWeek) {
            return true;
        } else {
            return false;
        }
    }
}
