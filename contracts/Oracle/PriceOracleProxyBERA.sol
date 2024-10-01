//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "../OpenZeppelin/Ownable2Step.sol";
import "./Interfaces/AggregatorV3Interface.sol";
import "./Interfaces/FlagsInterface.sol";
import "../CErc20.sol";
import "../CToken.sol";
import "../EIP20Interface.sol";
import "./Interfaces/PlvGLPOracleInterface.sol";
import "../Exponential.sol";
import "../SafeMath.sol";
import "@api3/contracts/api3-server-v1/proxies/interfaces/IProxy.sol";

contract PriceOracleProxyBERA is Ownable2Step, Exponential {
    using SafeMath for uint256;

    bool public constant isPriceOracle = true;

    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /// @notice ChainLink aggregator base, currently support USD and ETH
    enum AggregatorBase {
        USD,
        BERA
    }

    /// @notice Ether cToken address
    CToken public lberaAddress;

    struct AggregatorInfo {
        /// @notice The source address of the aggregator
        IProxy source;
        /// @notice The aggregator base
        AggregatorBase base;
    }

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorInfo) public aggregators;

    /// @notice The ETH-USD aggregator address
    IProxy public beraUsdAggregator;

    /**
     * @param beraUsdAggregator_ the address of the ETH/USD Chainlink aggregator
     */
    constructor(address beraUsdAggregator_, CToken lberaAddress_) {
        beraUsdAggregator = IProxy(beraUsdAggregator_);
        lberaAddress = lberaAddress_;
    }

    /**
     * @notice Get the underlying price of a listed cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(CToken cToken) public view returns (uint256) {
        address cTokenAddress = address(cToken);
        AggregatorInfo memory aggregatorInfo = aggregators[cTokenAddress];
        if (cToken == lberaAddress) {
            return 1e18;
        } else if (address(aggregatorInfo.source) != address(0)) {
            uint256 price = getPriceFromChainlink(aggregatorInfo.source);
            if (aggregatorInfo.base == AggregatorBase.USD) {
                // Convert the price to ETH based if it's USD based.
                price = div_(price, Exp({mantissa: getPriceFromChainlink(beraUsdAggregator)}));
                uint256 underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                return price * 10 ** (18 - underlyingDecimals);
            } else if (aggregatorInfo.base == AggregatorBase.BERA) {
                uint256 underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                return price * 10 ** (18 - underlyingDecimals);
            }
        }
        revert("Invalid Oracle Request");
    }

    /*** Internal functions ***/

    /**
     * @notice Get price from ChainLink
     * @param aggregator The ChainLink aggregator to get the price of
     * @return The price
     */
    function getPrice(IProxy aggregator) internal view returns (uint256) {
        (int224 price, uint256 timestamp) = IProxy(aggregator).read();
        //require(roundId == answeredInRound && startedAt == updatedAt, 'Price not fresh');
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(aggregator.decimals()));
    }

    /*** Admin or guardian functions ***/

    event AggregatorUpdated(address cTokenAddress, address source, AggregatorBase base);
    event SetGuardian(address guardian);
    event SetAdmin(address admin);

    /**
     * @notice Set ChainLink aggregators for multiple cTokens
     * @param cTokenAddresses The list of cTokens
     * @param sources The list of ChainLink aggregator sources
     * @param bases The list of ChainLink aggregator bases
     */
    function _setAggregators(
        address[] calldata cTokenAddresses,
        address[] calldata sources,
        AggregatorBase[] calldata bases
    ) external onlyOwner {
        require(cTokenAddresses.length == sources.length && cTokenAddresses.length == bases.length, "mismatched data");
        for (uint256 i = 0; i < cTokenAddresses.length; i++) {
            aggregators[cTokenAddresses[i]] = AggregatorInfo({
                source: AggregatorV3Interface(sources[i]),
                base: bases[i]
            });
            emit AggregatorUpdated(cTokenAddresses[i], sources[i], bases[i]);
        }
    }
}
