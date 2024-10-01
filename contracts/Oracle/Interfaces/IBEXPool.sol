//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface IBEXPool {
    function poolType(address pool) external view returns (uint256);
    function baseToken(address pool) external view returns (address);
    function quoteToken(address pool) external view returns (address);
}
