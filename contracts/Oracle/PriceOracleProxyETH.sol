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
import "./Interfaces/UniswapV2Interface.sol";

contract PriceOracleProxyETH is Ownable2Step, Exponential {
    using SafeMath for uint8;

    bool public constant isPriceOracle = true;
    bool public anchorsEnabled;

    uint256 private constant GRACE_PERIOD_TIME = 3600;
    uint256 public constant BASE = 1e18;

    uint256 public MAX_DEVIATION;
    uint8 public twapPeriod;
    uint8 public currentIndex;

    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// @notice ChainLink aggregator base, currently support USD and ETH
    enum ChainlinkAggregatorBase {
        USD,
        ETH
    }

    //we want to be able to make an observation on some source address (LP) and record the TWAP at that time
    //for our TWAP we will have a N hour moving average so we will take an observation once per hour and
    //continuously report a N point moving average (the average price of the asset over the last N hours).

    //at any time, we have a cumulative sum stored for a particular market which is the sum of N values in the
    //market's observation array. Starting at index 0 for N = 6:
    //0: first observation and store at index 0
    //1: second observation and store at index 1
    //..
    //5: sixth observation and store at index 5
    //6: seventh observation and store at index 0

    //this maintains a constant length array for the asset of length N and observation indices range from
    //0 to N-1. This is accomplished by continuously counting the parameter currentIndex and calculating the
    //modulo between the current index and N (i.e. mod currentIndex % N)

    struct Anchor {
        string name;
        IUniswapV2Pair source;
        uint256 cumulativeSum;
        uint256 anchorPrice;
        uint256 lastUpdateTimestamp;
        bool isInitialized;
    }

    mapping(address => Anchor) public anchors;

    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    mapping(address => Observation[]) public observations;

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
        ChainlinkAggregatorBase base;
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
        address glpOracleAddress_,
        uint8 twapPeriod_
    ) {
        ethUsdAggregator = AggregatorV3Interface(ethUsdAggregator_);
        sequencerAddress = sequencerAddress_;
        letherAddress = letherAddress_;
        lplvGLPAddress = lplvGLPAddress_;
        glpOracleAddress = glpOracleAddress_;
        twapPeriod = twapPeriod_;
        currentIndex = 0;
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
            price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator, cToken)}));
            return price;
        } else if (address(aggregatorInfo.source) != address(0)) {
            sequencerStatus = getSequencerStatus(sequencerAddress);
            uint256 price = getPriceFromChainlink(aggregatorInfo.source, cToken);
            if (sequencerStatus == false) {
                // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            } else if (aggregatorInfo.base == ChainlinkAggregatorBase.USD) {
                // Convert the price to ETH based if it's USD based.
                price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator, cToken)}));
                uint256 underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                return price * 10 ** (18 - underlyingDecimals);
            } else if (aggregatorInfo.base == ChainlinkAggregatorBase.ETH) {
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
    function getPriceFromChainlink(AggregatorV3Interface aggregator, CToken cToken) internal view returns (uint256) {
        (uint80 roundId, int256 price, uint startedAt, uint updatedAt, uint80 answeredInRound) = aggregator
            .latestRoundData();

        require(roundId == answeredInRound && startedAt == updatedAt, "Price not fresh");
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        uint256 priceScaled = uint256(price) * 10 ** (18 - uint256(aggregator.decimals()));

        if (anchorsEnabled) {
            uint256 anchorPrice;
            uint256 deviation;
            uint256 maxDeviation;
            anchorPrice = anchors[address(cToken)].anchorPrice;
            maxDeviation = (anchorPrice * MAX_DEVIATION) / BASE;

            if (anchorPrice > priceScaled) {
                deviation = anchorPrice - priceScaled;
            } else {
                deviation = priceScaled - anchorPrice;
            }

            if (deviation > maxDeviation) {
                return anchorPrice;
            }
        }
        return priceScaled;
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

    //Simple function to get price from an LP and store it as an observation in the array given the current index
    //to be fleshed out, currently a proof of concept
    //is it better to have the input be the source (ie the anchor is accessed outside of this function)
    //or is it better to take the ctoken address here, retrieve the anchor struct for the market and act accordingly?
    //i think the latter.
    function getObservation(CToken cToken) public returns (bool) {
        Anchor memory marketAnchor = anchors[address(cToken)];
        IUniswapV2Pair source = marketAnchor.source;
        uint256 price;
        address token0 = source.token0();
        (uint112 reserve0, uint112 reserve1, ) = source.getReserves();

        //calculate token price, to be fleshed out
        if (token0 != WETH) {
            price = (reserve0 * BASE) / reserve1;
        } else {
            price = (reserve1 * BASE) / reserve0;
        }

        if (currentIndex == 0) {
            observations[address(cToken)] = new Observation[](twapPeriod);
        }

        uint8 indexMod = currentIndex % twapPeriod;

        Observation[] memory marketObservations = observations[address(cToken)];
        Observation memory marketObservationCurrentIndex = marketObservations[indexMod];
        uint256 priceChop = marketObservationCurrentIndex.price;

        observations[address(cToken)][indexMod].price = price;
        observations[address(cToken)][indexMod].timestamp = block.timestamp;
        anchors[address(cToken)].cumulativeSum = marketAnchor.cumulativeSum + price - priceChop;
        return true;
    }

    //view function to see current twap price
    function getTWAPPrice(CToken cToken) public view returns (uint256) {
        return anchors[address(cToken)].anchorPrice;
    }

    //function to update TWAP, to be permissioned
    function updateTWAPPrice(CToken cToken) public returns (bool) {
        Anchor memory marketAnchor = anchors[address(cToken)];
        uint256 cumulativeSum = marketAnchor.cumulativeSum;
        uint256 price = cumulativeSum / twapPeriod;
        anchors[address(cToken)].anchorPrice = price;
        return true;
    }

    function updateAnchors(CToken[] memory cTokens) external returns (bool) {
        for (uint i = 0; i < cTokens.length; i++) {
            require(getObservation(cTokens[i]), "Observation update failed");
            require(updateTWAPPrice(cTokens[i]), "TWAP Update failed");
        }
        currentIndex += 1;
        return true;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        if (keccak256(bytes(a)) == keccak256(bytes(b))) {
            return true;
        } else {
            return false;
        }
    }

    /*** Admin or guardian functions ***/

    event AggregatorUpdated(address cTokenAddress, address source, ChainlinkAggregatorBase base);
    event SetGuardian(address guardian);
    event SetAdmin(address admin);
    event newLodeOracle(address newLodeOracle);
    event newGlpOracle(address newGlpOracle);
    event AnchorUpdated(string name, IUniswapV2Pair source);

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
        ChainlinkAggregatorBase[] calldata bases
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

    function _updateAnchor(CToken cToken, IUniswapV2Pair source, string memory name) external onlyOwner {
        require(address(source) != address(0) && address(cToken) != address(0), "Invalid input(s)");
        anchors[address(cToken)].name = name;
        anchors[address(cToken)].source = source;
        emit AnchorUpdated(name, source);
    }
}
