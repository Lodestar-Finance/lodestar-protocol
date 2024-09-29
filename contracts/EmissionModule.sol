//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EmissionsModule is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public comptroller;
    address public emissionsHandler;

    uint256 public pendingFees;

    IERC20 public emissionsToken;
    IERC20 public feeToken;

    //add events

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

        IERC20(comptroller).safeTransfer(msg.sender, amount);
    }

    function handleFees() external nonReentrant whenNotPaused {
        //add fee handling logic
    }

    //** ADMIN FUNCTIONS */

    function setComptroller(address comptroller_) external onlyOwner {
        comptroller = comptroller_;
    }

    function setEmissionsHandler(address emissionsHandler_) external onlyOwner {
        emissionsHandler = emissionsHandler_;
    }

    function setEmissionsToken(IERC20 emissionsToken_) external onlyOwner {
        emissionsToken = emissionsToken_;
    }

    function setFeeToken(IERC20 feeToken_) external onlyOwner {
        feeToken = feeToken_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
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
