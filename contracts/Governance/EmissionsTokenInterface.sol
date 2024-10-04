// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface EmissionsTokenInterface is IERC20 {
    function burn(uint256 amount) external;
}
