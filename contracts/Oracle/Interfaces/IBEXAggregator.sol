//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface IBEXAggregator {
    function getPrice(address pool) external view returns (uint256);
}
