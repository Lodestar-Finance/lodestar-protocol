//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./ComptrollerInterface.sol";
import "./Oracle/Interfaces/IPOPE.sol";

contract EmissionsModule is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ComptrollerInterface public comptroller;
    address public emissionsHandler;
    IPOPE public oracle;

    uint256 public pendingFees;

    IERC20 public emissionsToken;
    IERC20 public feeToken;

    event ComptrollerSet(address indexed comptroller);
    event EmissionsHandlerSet(address indexed emissionsHandler);
    event EmissionsTokenSet(address indexed emissionsToken);
    event FeeTokenSet(address indexed feeToken);
    event OracleSet(address indexed oracle);

    event Claimed(address indexed account, uint256 amount);
    event FeesHandled(uint256 amount);

    constructor() Ownable() {}

    function getClaimable(address account_) public view returns (uint256) {
        return 0;
    }

    function getFee(uint256 amount_) public view returns (uint256) {
        return 0;
    }

    function claim() external nonReentrant whenNotPaused {
        uint256 amount = getClaimable(msg.sender);
        require(amount > 0, "No claimable emissions");

        address(comptroller).transfer(msg.sender, amount);
    }

    function handleFees() external nonReentrant whenNotPaused {
        //add fee handling logic
    }

    //** ADMIN FUNCTIONS */

    function setComptroller(address comptroller_) external onlyOwner {
        require(comptroller_ != address(0), "Invalid comptroller");
        //any other comptroller sanity checks?
        comptroller = comptroller_;
        //if the unitroller changes, we want to also make sure we still have the correct oracle
        IPOPE pendingOracle = comptroller.oracle();
        //run some sanity checks here? Get price of protocol token and make sure its not 0?
        oracle = pendingOracle;
        emit ComptrollerSet(comptroller_);
        emit OracleSet(oracle);
    }

    function setEmissionsHandler(address emissionsHandler_) external onlyOwner {
        require(emissionsHandler_ != address(0), "Invalid emissions handler");
        emissionsHandler = emissionsHandler_;
        emit EmissionsHandlerSet(emissionsHandler_);
    }

    function setEmissionsToken(IERC20 emissionsToken_) external onlyOwner {
        require(address(emissionsToken_) != address(0), "Invalid emissions token");
        emissionsToken = emissionsToken_;
        emit EmissionsTokenSet(address(emissionsToken_));
    }

    function setFeeToken(IERC20 feeToken_) external onlyOwner {
        require(address(feeToken_) != address(0), "Invalid fee token");
        feeToken = feeToken_;
        emit FeeTokenSet(address(feeToken_));
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused();
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused();
    }

    function withdraw(address token_, uint256 amount_) external onlyOwner {
        IERC20(token_).safeTransfer(msg.sender, amount_);
    }

    function withdrawNative() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function addPendingFees(uint256 amount_) external onlyOwner {
        feeToken.safeTransferFrom(msg.sender, address(this), amount_);
        pendingFees += amount_;
    }

    receive() external payable {}

    fallback() external payable {}
}
