// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

interface StdReferenceInterface {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(
        string calldata _base,
        string calldata _quote
    ) external view returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(
        string[] calldata _bases,
        string[] calldata _quotes
    ) external view returns (ReferenceData[] memory);
}
