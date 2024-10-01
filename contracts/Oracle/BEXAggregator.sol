//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0

import "./Interfaces/ICrocQuery.sol";
import "./Interfaces/IBEXPool.sol";

contract BEXAggregator {

    ICrocQuery public crocQuery;

    constructor(ICrocQuery _crocQuery) {
        crocQuery = _crocQuery;
    }

    function getPrice(IBEXPool pool) public view returns (uint256) {
        uint256 poolIdx = pool.poolType(pool);
        address base = pool.baseToken(pool);
        address quote = pool.quoteToken(pool);
        uint256 price = crocQuery.queryPrice(base, quote, poolIdx);
        require(price > 0, "Invalid price");
        return price;
    }
}