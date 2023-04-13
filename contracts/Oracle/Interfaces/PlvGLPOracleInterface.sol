// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

abstract contract PlvGLPOracleInterface {
    bool public constant isGLPOracle = true;

    function getGLPPrice() external view virtual returns (uint256);

    function getPlvGLPPrice() external view virtual returns (uint256);
}
