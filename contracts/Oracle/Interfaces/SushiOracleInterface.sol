// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

abstract contract SushiOracleInterface {
    bool public constant isSushiOracle = true;

    function price() external view virtual returns (uint256);
}
