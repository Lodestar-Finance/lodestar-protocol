//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPOPE {
    function getUnderlyingPrice(address cToken_) external view returns (uint256);
}
