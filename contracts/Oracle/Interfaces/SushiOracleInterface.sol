pragma solidity ^0.8.10;

interface SushiOracleInterface {

    function price() external view returns (uint256);

}