pragma solidity ^0.8.10;
import "../EIP20Interface.sol";
import "./Interfaces/GLPManagerInterface.sol";
import "./Interfaces/plvGLPInterface.sol";

contract GLPOracle {
    address public admin;

    address public GLP;

    address public GLPManager;

    address public plvGLP;

    uint256 private constant DECIMAL_DIFFERENCE = 1e6;

    uint256 private constant BASE = 1e18;

    event newGLPAddress(address newGLPAddress);

    event newGLPManagerAddress(address newGLPManagerAddress);

    event newAdmin(address newAdmin);

    event newPlvGLPAddress(address newPlvGLPAddress);

    constructor(
        address admin_,
        address GLPAddress_,
        address GLPManagerAddress_,
        address plvGLPAddress_
    ) {
        admin = admin_;
        GLP = GLPAddress_;
        GLPManager = GLPManagerAddress_;
        plvGLP = plvGLPAddress_;
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

    function getPlvGLPPrice() public view returns (uint256) {
        uint256 exchangeRate = getPlutusExchangeRate();

        uint256 glpPrice = getGLPPrice();

        uint256 price = (exchangeRate * glpPrice) / BASE;

        return price;
    }

    function updateAdmin(address _newAdmin) public returns (address) {
        require(
            msg.sender == admin,
            "Only the current admin is authorized to change the admin"
        );
        admin = _newAdmin;
        emit newAdmin(_newAdmin);
        return _newAdmin;
    }

    function updateGlpAddress(address _newGlpAddress) public returns (address) {
        require(
            msg.sender == admin,
            "Only the admin can change the GLP contract address"
        );
        GLP = _newGlpAddress;
        emit newGLPAddress(_newGlpAddress);
        return _newGlpAddress;
    }

    function updateGlpManagerAddress(
        address _newGlpManagerAddress
    ) public returns (address) {
        require(
            msg.sender == admin,
            "Only the admin can change the GLP Manager contract address"
        );
        GLPManager = _newGlpManagerAddress;
        emit newGLPManagerAddress(_newGlpManagerAddress);
        return _newGlpManagerAddress;
    }

    function updatePlvGlpAddress(
        address _newPlvGlpAddress
    ) public returns (address) {
        require(
            msg.sender == admin,
            "Only the admin can change the plvGLP contract address"
        );
        plvGLP = _newPlvGlpAddress;
        emit newPlvGLPAddress(_newPlvGlpAddress);
        return _newPlvGlpAddress;
    }
}
