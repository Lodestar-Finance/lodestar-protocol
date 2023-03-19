//SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "./Interfaces/AggregatorV3Interface.sol";
import "./Interfaces/FlagsInterface.sol";
import "../CErc20.sol";
import "../CToken.sol";
import "../EIP20Interface.sol";
import "./Interfaces/PlvGLPOracleInterface.sol";
import "../ExponentialNoError.sol";
import "./SushiOracle.sol";
import "./Interfaces/SushiOracleInterface.sol";

contract PriceOracleProxyETH is ExponentialNoError {
    error ChainlinkFeedsNotBeingUpdated();
    error InvalidOracleRequest();
    error NotAdmin();
    error InvalidContract();
    error InvalidPrice();
    error NotAdminOrGuardian();
    error MismatchedData();

    bool public constant isPriceOracle = true;

    /// @notice ChainLink aggregator base, currently support USD and ETH
    enum AggregatorBase {
        USD,
        ETH
    }

    /// @notice Admin address
    address public admin;

    /// @notice Guardian address
    address public guardian;

    /// @notice Ether cToken address
    address public letherAddress;

    /// @notice plvGLP cToken address
    address public lplvGLPAddress;

    /// @notice GLP Oracle address
    address public glpOracleAddress;

    /// @notice Chainlink L2 sequencer aggregator address
    address public sequencerAddress;

    /// @notice LODE token
    address public lLodeAddress;

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
     * @param admin_ The address of admin to set aggregators
     * @param ethUsdAggregator_ the address of the ETH/USD Chainlink aggregator
     * @param sequencerAddress_ the address of the Chainlink L2 sequencer aggregator
     * @param letherAddress_ the address of the Ether cToken
     * @param lplvGLPAddress_ the address of the plvGLP cToken
     * @param glpOracleAddress_ the address of the GLP Oracle contract
     * @param lodeOracle_ the address of the LODE oracle contract
     */
    constructor(
        address admin_,
        address ethUsdAggregator_,
        address sequencerAddress_,
        address letherAddress_,
        address lplvGLPAddress_,
        address glpOracleAddress_,
        address lodeOracle_
    ) payable {
        admin = admin_;
        ethUsdAggregator = AggregatorV3Interface(ethUsdAggregator_);
        sequencerAddress = sequencerAddress_;
        letherAddress = letherAddress_;
        lplvGLPAddress = lplvGLPAddress_;
        glpOracleAddress = glpOracleAddress_;
        lodeOracle = lodeOracle_;
    }

    /**
     * @notice Get the underlying price of a listed cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(CToken cToken) public view returns (uint256) {
        address cTokenAddress = address(cToken);
        AggregatorInfo memory aggregatorInfo = aggregators[cTokenAddress];
        if (cTokenAddress == letherAddress) {
            uint256 price = 1e18;
            return price;
        } else if (cTokenAddress == lplvGLPAddress) {
            uint256 price = getPlvGLPPrice();
            price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)}));
            return price;
        } else if (address(aggregatorInfo.source) != address(0)) {
            bool sequencerStatus = getSequencerStatus(sequencerAddress);
            uint256 price = getPriceFromChainlink(aggregatorInfo.source);
            if (!sequencerStatus) {
                // If flag is raised we shouldn't perform any critical operations
                revert ChainlinkFeedsNotBeingUpdated();
            } else if (aggregatorInfo.base == AggregatorBase.USD) {
                // Convert the price to ETH based if it's USD based.
                price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)}));
                uint256 underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                return price * 10 ** (18 - underlyingDecimals);
            } else if (aggregatorInfo.base == AggregatorBase.ETH) {
                return price;
            }
        }
        revert InvalidOracleRequest();
    }

    /*** Internal functions ***/

    /**
     * @notice Get price from ChainLink
     * @param aggregator The ChainLink aggregator to get the price of
     * @return The price
     */
    function getPriceFromChainlink(AggregatorV3Interface aggregator) internal view returns (uint256) {
        (, int256 price, , , ) = aggregator.latestRoundData();
        if (price <= 0) revert InvalidPrice();

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(aggregator.decimals()));
    }

    /**
     * @notice Get the price of plvGLP
     * @return The price of plvGLP already scaled to 18 decimals
     */
    function getPlvGLPPrice() internal view returns (uint256) {
        uint256 price = PlvGLPOracleInterface(glpOracleAddress).getPlvGLPPrice();
        if (price <= 0) revert InvalidPrice();
        return price;
    }

    /**
     * @notice Get price of LODE token
     * @return the price of LODE in wei
     */
    function getLodePrice() public view returns (uint256) {
        uint256 price = SushiOracleInterface(lodeOracle).price();
        return price;
    }

    /**
     * @notice Get L2 sequencer status from Chainlink sequencer aggregator
     * @param sequencer the address of the Chainlink sequencer aggregator ("sequencerAddress" in constructor)
     * @return the L2 sequencer status as a boolean (true = the sequencer is up, false = the sequencer is down)
     */
    function getSequencerStatus(address sequencer) internal view returns (bool) {
        bool status;
        (, int256 answer, , , ) = AggregatorV3Interface(sequencer).latestRoundData();
        if (answer == 0) {
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
     * @param _guardian The new guardian
     */
    function _setGuardian(address _guardian) external {
        if (msg.sender != admin) revert NotAdmin();
        guardian = _guardian;
        emit SetGuardian(_guardian);
    }

    /**
     * @notice Set admin for price oracle proxy
     * @param _admin The new admin
     */
    function _setAdmin(address _admin) external {
        if (msg.sender != admin) revert NotAdmin();
        admin = _admin;
        emit SetAdmin(_admin);
    }

    /**
     * @notice Set guardian for price oracle proxy
     * @param _newLodeOracle The new LODE oracle contract
     */
    function _setLodeOracle(SushiOracleInterface _newLodeOracle) external {
        if (msg.sender != admin) revert NotAdmin();
        if (!_newLodeOracle.isSushiOracle()) revert InvalidContract();
        lodeOracle = address(_newLodeOracle);
        emit newLodeOracle(address(_newLodeOracle));
    }

    /**
     * @notice Set guardian for price oracle proxy
     * @param _newGlpOracle The new LODE oracle contract
     */
    function _setGlpOracle(PlvGLPOracleInterface _newGlpOracle) external {
        if (msg.sender != admin) revert NotAdmin();
        if (!_newGlpOracle.isGLPOracle()) revert InvalidContract();
        glpOracleAddress = address(_newGlpOracle);
        emit newGlpOracle(address(_newGlpOracle));
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
    ) external {
        if (msg.sender != admin && msg.sender != guardian) revert NotAdminOrGuardian();
        if (cTokenAddresses.length != sources.length || cTokenAddresses.length != bases.length) revert MismatchedData();
        for (uint256 i; i < cTokenAddresses.length;) {
            if (sources[i] != address(0)) {
                if (msg.sender != admin) revert NotAdmin();
            }
            aggregators[cTokenAddresses[i]] = AggregatorInfo({
                source: AggregatorV3Interface(sources[i]),
                base: bases[i]
            });
            emit AggregatorUpdated(cTokenAddresses[i], sources[i], bases[i]);

            unchecked { ++i; }
        }
    }
}
