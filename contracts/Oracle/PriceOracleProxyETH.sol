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

contract PriceOracleProxyETH is Ownable2Step, Exponential {
    using SafeMath for uint256;

    bool public constant isPriceOracle = true;

    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /// @notice ChainLink aggregator base, currently support USD and ETH
    enum AggregatorBase {
        USD,
        ETH
    }

    /// @notice Ether cToken address
    address public letherAddress;

    /// @notice plvGLP cToken address
    address public lplvGLPAddress;

    /// @notice GLP Oracle address
    address public glpOracleAddress;

    /// @notice Chainlink L2 sequencer aggregator address
    address public sequencerAddress;

    /// @notice LODE oracle address (SushiOracle)
    address public lodeOracle;

    uint256 lodePrice;

    struct AggregatorInfo {
        /// @notice The source address of the aggregator
        AggregatorV3Interface source;
        /// @notice The aggregator base
        AggregatorBase base;
    }

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorInfo) public aggregators;

    /// @notice The ETH-USD aggregator address
    AggregatorV3Interface public ethUsdAggregator;

    /**
     * @param ethUsdAggregator_ the address of the ETH/USD Chainlink aggregator
     * @param sequencerAddress_ the address of the Chainlink L2 sequencer aggregator
     * @param letherAddress_ the address of the Ether cToken
     * @param lplvGLPAddress_ the address of the plvGLP cToken
     * @param glpOracleAddress_ the address of the GLP Oracle contract
     */
    constructor(
        address ethUsdAggregator_,
        address sequencerAddress_,
        address letherAddress_,
        address lplvGLPAddress_,
        address glpOracleAddress_
    ) {
        ethUsdAggregator = AggregatorV3Interface(ethUsdAggregator_);
        sequencerAddress = sequencerAddress_;
        letherAddress = letherAddress_;
        lplvGLPAddress = lplvGLPAddress_;
        glpOracleAddress = glpOracleAddress_;
    }

    /**
     * @notice Get the underlying price of a listed cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(CToken cToken) public view returns (uint256) {
        address cTokenAddress = address(cToken);
        AggregatorInfo memory aggregatorInfo = aggregators[cTokenAddress];
        bool sequencerStatus;
        if (cTokenAddress == letherAddress) {
            uint256 price = 1e18;
            return price;
        } else if (cTokenAddress == lplvGLPAddress) {
            sequencerStatus = getSequencerStatus(sequencerAddress);
            if (sequencerStatus == false) {
                // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            }
            uint256 price = getPlvGLPPrice();
            price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)}));
            return price;
        } else if (address(aggregatorInfo.source) != address(0)) {
            sequencerStatus = getSequencerStatus(sequencerAddress);
            uint256 price = getPriceFromChainlink(aggregatorInfo.source);
            if (sequencerStatus == false) {
                // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            } else if (aggregatorInfo.base == AggregatorBase.USD) {
                // Convert the price to ETH based if it's USD based.
                price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)}));
                uint256 underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                return price * 10 ** (18 - underlyingDecimals);
            } else if (aggregatorInfo.base == AggregatorBase.ETH) {
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
    function getPriceFromChainlink(AggregatorV3Interface aggregator) internal view returns (uint256) {
        (uint80 roundId, int256 price, uint startedAt, uint updatedAt, uint80 answeredInRound) = aggregator
            .latestRoundData();
        require(roundId == answeredInRound && startedAt == updatedAt, "Price not fresh");
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(aggregator.decimals()));
    }

    /**
     * @notice Get the price of plvGLP
     * @return The price of plvGLP already scaled to 18 decimals
     */
    function getPlvGLPPrice() internal view returns (uint256) {
        uint256 price = PlvGLPOracleInterface(glpOracleAddress).getPlvGLPPrice();
        require(price > 0, "invalid price");
        return price;
    }

    /**
     * @notice Get L2 sequencer status from Chainlink sequencer aggregator
     * @param sequencer the address of the Chainlink sequencer aggregator ("sequencerAddress" in constructor)
     * @return the L2 sequencer status as a boolean (true = the sequencer is up, false = the sequencer is down)
     */
    function getSequencerStatus(address sequencer) internal view returns (bool) {
        bool status;
        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(sequencer).latestRoundData();
        if (answer == 0 && block.timestamp - startedAt > GRACE_PERIOD_TIME) {
            status = true;
        } else if (answer == 1) {
            status = false;
        }
        return status;
    }

    /*** Admin or guardian functions ***/

    event AggregatorUpdated(address cTokenAddress, address source, AggregatorBase base);
    event SetGuardian(address guardian);
    event SetAdmin(address admin);
    event newLodeOracle(address newLodeOracle);
    event newGlpOracle(address newGlpOracle);

    /**
     * @notice Set guardian for price oracle proxy
     * @param _newGlpOracle The new LODE oracle contract
     */
    function _setGlpOracle(PlvGLPOracleInterface _newGlpOracle) external onlyOwner {
        require(_newGlpOracle.isGLPOracle(), "Invalid Contract");
        glpOracleAddress = address(_newGlpOracle);
        emit newGlpOracle(glpOracleAddress);
    }

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
