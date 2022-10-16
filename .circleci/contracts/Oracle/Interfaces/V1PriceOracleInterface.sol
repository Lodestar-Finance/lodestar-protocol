pragma solidity ^0.8.10;

interface V1PriceOracleInterface {
    function assetPrices(address asset) external view returns (uint256);
}