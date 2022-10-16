pragma solidity ^0.8.10;

interface GLPManagerInterface {
    function getAum(bool maximise) external view returns (uint256);
}