//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "../EIP20Interface.sol";
import "./Interfaces/UniswapV2Interface.sol";

contract SushiOracle {
    error NotAdmin();

    bool public constant isSushiOracle = true;

    address public immutable tokenA;

    address public immutable tokenB;

    address public poolContract;

    address public admin;

    event poolContractUpdated(address newPoolContract);

    event adminUpdated(address newAdmin);

    constructor(address tokenA_, address tokenB_, address poolContract_) payable {
        admin = msg.sender;
        tokenA = tokenA_;
        tokenB = tokenB_;
        poolContract = poolContract_;
    }

    function getTokenBalance(address tokenAddress) public view returns (uint256) {
        uint256 balance = EIP20Interface(tokenAddress).balanceOf(poolContract);
        return balance;
    }

    function price() public view returns (uint256) {
        uint256 balanceA = getTokenBalance(tokenA);
        uint256 balanceB = getTokenBalance(tokenB);
        return (balanceA * 1e18) / balanceB;
    }

    //ADMIN FUNCTIONS

    function _setPoolContract(address newPoolContract) public {
        if (msg.sender != admin) revert NotAdmin();
        poolContract = newPoolContract;
        emit poolContractUpdated(newPoolContract);
    }

    function _setAdmin(address newAdmin) public {
        if (msg.sender != admin) revert NotAdmin();
        admin = newAdmin;
        emit adminUpdated(newAdmin);
    }
}
