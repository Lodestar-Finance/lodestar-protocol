//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import '../EIP20Interface.sol';
import '../Exponential.sol';
import './Interfaces/UniswapV2Interface.sol';


contract SushiOracle is Exponential {

    address public tokenA;

    address public tokenB;

    address public poolContract;

    address public admin;

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

    function getTokenAddress (uint tokenId) public view returns (address result) {
        if (tokenId == 0) {
            result =  IUniswapV2Pair(poolContract).token0();
            return result;
        }
        else if (tokenId == 1) {
            result = IUniswapV2Pair(poolContract).token1();
            return result;
        }

    }


    function getTokenBalance (address tokenAddress) public view returns (uint256) {
        uint256 balance = EIP20Interface(tokenAddress).balanceOf(poolContract);
        return balance;
    }

    function price () public view returns (uint256 price) {
        address token0 = getTokenAddress(0);
        address token1 = getTokenAddress(1);

        if (tokenA != token0 || tokenB != token1 ) {
            revert('Requested token not part of this pool');
        }

        uint256 balanceA = getTokenBalance(tokenA);
        uint256 balanceB = getTokenBalance(tokenB);

        price = balanceA / balanceB;

        return price;
    }

    //ADMIN FUNCTIONS
    





}