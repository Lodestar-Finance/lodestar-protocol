pragma solidity ^0.8.10;

interface XSushiExchangeRateInterface {
    function getExchangeRate() external view returns (uint256);
}