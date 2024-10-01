//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface ILens {
    function getPendingRewards(address user) external returns (uint256);
}
