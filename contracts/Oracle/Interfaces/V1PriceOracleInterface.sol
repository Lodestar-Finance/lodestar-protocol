//SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface V1PriceOracleInterface {
    function assetPrices(address asset) external view returns (uint256);

    function getPrice(address asset) external view returns (uint256);

    function setPrice(address asset, uint256 requestedPriceMantissa) external returns (uint256);
}
