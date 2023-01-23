// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;
import "../EIP20Interface.sol";
import "./Interfaces/GLPManagerInterface.sol";
import "./Interfaces/plvGLPInterface.sol";

contract GLPOracle {
    bool public constant isGLPOracle = true;

    struct Observation {
        uint timestamp;
        uint256 cumulativeRate;
    }

    mapping(address => Observation[]) public observationList;

    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint public windowSize;
    // the number of observations stored for each pair, i.e. how many price observations are stored for the window.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public granularity;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint public periodSize;

    uint256 cumulativeRate;

    address public admin;

    address public GLP;

    address public GLPManager;

    address public plvGLP;

    uint256 private constant DECIMAL_DIFFERENCE = 1e6;

    uint256 private constant BASE = 1e18;

    event updatePosted(address market, uint256 timestamp, uint256 cumulativeRate);

    event newGLPAddress(address newGLPAddress);

    event newGLPManagerAddress(address newGLPManagerAddress);

    event newAdmin(address newAdmin);

    event newPlvGLPAddress(address newPlvGLPAddress);

    event windowSizeUpdated(uint oldWindowSize, uint newWindowSize);

    event granularityUpdated(uint8 oldGranularity, uint8 newGranularity);

    event periodSizeUpdated(uint oldPeriodSize, uint newPeriodSize);

    constructor(
        address admin_,
        address GLPAddress_,
        address GLPManagerAddress_,
        address plvGLPAddress_,
        uint windowSize_,
        uint8 granularity_
    ) {
        require(granularity_ > 1, "GLPOracle: GRANULARITY");
        require(
            (periodSize = windowSize_ / granularity_) * granularity_ == windowSize_,
            "GLPOracle: WINDOW_NOT_EVENLY_DIVISIBLE"
        );
        admin = admin_;
        GLP = GLPAddress_;
        GLPManager = GLPManagerAddress_;
        plvGLP = plvGLPAddress_;
        windowSize = windowSize_;
        granularity = granularity_;
        cumulativeRate = 0;
    }

    function getGLPPrice() public view returns (uint256) {
        //retrieve the minimized AUM from GLP Manager Contract
        uint256 glpAUM = GLPManagerInterface(GLPManager).getAum(false);

        //retrieve the total supply of GLP
        uint256 glpSupply = EIP20Interface(GLP).totalSupply();

        //GLP Price = AUM / Total Supply
        uint256 price = (glpAUM / glpSupply) * DECIMAL_DIFFERENCE;

        return price;
    }

    function getPlutusExchangeRate() public view returns (uint256) {
        //retrieve total assets from plvGLP contract
        uint256 totalAssets = plvGLPInterface(plvGLP).totalAssets();

        //retrieve total supply from plvGLP contract
        uint256 totalSupply = EIP20Interface(plvGLP).totalSupply();

        //plvGLP/GLP Exchange Rate = Total Assets / Total Supply
        uint256 exchangeRate = (totalAssets * BASE) / totalSupply;

        return exchangeRate;
    }

    function getCumulativeExchangeRate() internal returns (uint256) {
        uint256 currentExchangeRate = getPlutusExchangeRate();
        cumulativeRate = cumulativeRate + currentExchangeRate;
        return cumulativeRate;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) public view returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow() private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = observationList[plvGLP][firstObservationIndex];
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update() external {
        // populate the array with empty observations (first call only)
        for (uint i = observationList[plvGLP].length; i < granularity; i++) {
            observationList[plvGLP].push();
        }

        // get the observation for the current period
        uint8 observationIndex = observationIndexOf(block.timestamp);
        Observation storage observation = observationList[plvGLP][observationIndex];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            uint256 cumulativeRateCurrent = getCumulativeExchangeRate();
            observation.timestamp = block.timestamp;
            observation.cumulativeRate = cumulativeRateCurrent;
        }

        emit updatePosted(plvGLP, observation.timestamp, observation.cumulativeRate);
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAverageRate(
        uint256 cumulativeRateStart,
        uint256 cumulativeRateEnd,
        uint timeElapsed
    ) private pure returns (uint256) {
        uint256 averageRate = uint256((cumulativeRateEnd - cumulativeRateStart) / timeElapsed);
        return averageRate;
    }

    function getPlvGLPPrice() public view returns (uint256) {
        Observation storage firstObservation = getFirstObservationInWindow();
        uint timeElapsed = block.timestamp - firstObservation.timestamp;
        require(timeElapsed <= windowSize, "GLPOracle: MISSING_HISTORICAL_OBSERVATION");
        // should never happen.
        require(timeElapsed >= windowSize - periodSize * 2, "GLPOracle: UNEXPECTED_TIME_ELAPSED");
        uint256 currentCumulativeRate = cumulativeRate;
        uint256 averageExchangeRate = computeAverageRate(
            firstObservation.cumulativeRate,
            currentCumulativeRate,
            timeElapsed
        );

        uint256 glpPrice = getGLPPrice();

        uint256 price = (averageExchangeRate * glpPrice) / BASE;

        return price;
    }

    //*** ADMIN FUNCTIONS ***

    function _updateAdmin(address _newAdmin) external {
        require(msg.sender == admin, "Only the current admin is authorized to change the admin");
        admin = _newAdmin;
        emit newAdmin(_newAdmin);
    }

    function _updateGlpAddress(address _newGlpAddress) external {
        require(msg.sender == admin, "Only the admin can change the GLP contract address");
        GLP = _newGlpAddress;
        emit newGLPAddress(_newGlpAddress);
    }

    function _updateGlpManagerAddress(address _newGlpManagerAddress) external {
        require(msg.sender == admin, "Only the admin can change the GLP Manager contract address");
        GLPManager = _newGlpManagerAddress;
        emit newGLPManagerAddress(_newGlpManagerAddress);
    }

    function _updatePlvGlpAddress(address _newPlvGlpAddress) external {
        require(msg.sender == admin, "Only the admin can change the plvGLP contract address");
        plvGLP = _newPlvGlpAddress;
        emit newPlvGLPAddress(_newPlvGlpAddress);
    }

    function _updateWindowSize(uint _newWindowSize) external {
        require(msg.sender == admin, "Only the admin can change the plvGLP contract address");
        uint oldWindowSize = windowSize;
        windowSize = _newWindowSize;
        emit windowSizeUpdated(oldWindowSize, windowSize);
    }

    function _updateGranularity(uint8 _newGranularity) external {
        require(msg.sender == admin, "Only the admin can change the plvGLP contract address");
        uint8 oldGranularity = granularity;
        granularity = _newGranularity;
        emit granularityUpdated(oldGranularity, granularity);
    }

    function _updatePeriodSize(uint _newPeriodSize) external {
        require(msg.sender == admin, "Only the admin can change the plvGLP contract address");
        uint oldPeriodSize = periodSize;
        periodSize = _newPeriodSize;
        emit windowSizeUpdated(oldPeriodSize, periodSize);
    }
}
