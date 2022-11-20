//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import '../EIP20Interface.sol';
import '../Exponential.sol';
import './Interfaces/UniswapV2Interface.sol';


contract SushiOracle is Exponential {

    address public immutable tokenA;

    address public immutable tokenB;

    address public poolContract;

    address public admin;

    event poolContractUpdated (address newPoolContract);

    event adminUpdated (address newAdmin);

    constructor (
        address tokenA_,
        address tokenB_,
        address poolContract_
    ) {
        admin = msg.sender;
        tokenA = tokenA_;
        tokenB = tokenB_;
        poolContract = poolContract_;
    }


    function getTokenBalance (address tokenAddress) public view returns (uint256) {
        uint256 balance = EIP20Interface(tokenAddress).balanceOf(poolContract);
        return balance;
    }

    function price () public view returns (uint256 price) {

        uint256 balanceA = getTokenBalance(tokenA);
        uint256 balanceB = getTokenBalance(tokenB);

        price = balanceB / balanceA;

        return price;
    }

    //ADMIN FUNCTIONS
    

    function _setPoolContract(address newPoolContract) public {
        require(msg.sender == admin, "Only the admin can update the pool contract.");

        poolContract = newPoolContract;

        emit poolContractUpdated(newPoolContract);

    }

    function _setAdmin(address newAdmin) public {
        require(msg.sender == admin, "Only the admin can update the admin");

        admin = newAdmin;

        emit adminUpdated(newAdmin);
    }



}