pragma solidity ^0.8.10;

interface GLPOracleInterface {
    function getGLPPrice() external view returns (uint256);

    function getPlvGLPPrice() external view returns (uint256);
}