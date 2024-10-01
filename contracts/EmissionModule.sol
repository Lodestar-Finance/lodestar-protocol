//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./util/StorageAccessible.sol";

import "./ComptrollerInterface.sol";
import "./Oracle/Interfaces/IBEXAggregator.sol";
import "./Lens/ILens.sol";

contract EmissionsModule is Ownable2Step, Pausable, ReentrancyGuard, StorageAccessible {
    using SafeERC20 for IERC20;

    ComptrollerInterface public comptroller;
    address public emissionsHandler;
    IBEXAggregator public oracle;
    ILens public lens;

    uint256 public pendingFees;
    uint256 FEE_PERCENTAGE;

    IERC20 public emissionsToken;
    IERC20 public feeToken;
    address public pool;

    mapping(address => bool) public isExemptFromFees;

    event ComptrollerSet(address indexed comptroller);
    event EmissionsHandlerSet(address indexed emissionsHandler);
    event EmissionsTokenSet(address indexed emissionsToken);
    event FeeTokenSet(address indexed feeToken);
    event OracleSet(address indexed oracle);
    event FeePercentageSet(uint256 feePercentage);
    event LensSet(address indexed lens);
    event Claimed(address indexed account, uint256 amount);
    event FeesHandled(uint256 amount);

    //emissions handler intentionally not set in constructor
    constructor(
        ComptrollerInterface comptroller_,
        IBEXAggregator emissionsTokenOracle,
        uint256 feePercentage,
        IERC20 emissionsToken_,
        IERC20 feeToken_,
        address pool_
    ) Ownable() {
        comptroller = comptroller_;
        oracle = emissionsTokenOracle;
        FEE_PERCENTAGE = feePercentage;
        emissionsToken = emissionsToken_;
        feeToken = feeToken_;
        pool = pool_;
    }

    function getClaimable(address account_) public returns (uint256) {
        bytes memory data = abi.encodeWithSelector(ILens.getPendingRewards.selector, account_);
        bytes memory response = simulate(address(lens), data);
        return abi.decode(response, (uint256));
    }

    function getFee(uint256 amount_) public view returns (uint256) {
        uint256 price = oracle.getPrice(pool);
        //assuming the price is scaled to 18 decimals, we need to scale it back to 18 after multiplying
        uint256 fee = (amount_ * price * FEE_PERCENTAGE) / 1e36;
    }

    function claim() external payable nonReentrant whenNotPaused {
        uint256 amount = getClaimable(msg.sender);
        require(amount > 0, "No claimable emissions");
        if (isExemptFromFees[msg.sender]) {
            comptroller.claimComp(msg.sender);
            return;
        } else {
            uint256 fee = getFee(amount);
            require(fee > 0, "Fee is 0");
            if (msg.value > 0) {
                require(msg.value >= fee, "Insufficient funds");
                //if the user wants to pay in native tokens we need to wrap them before anything else
                //TODO:wrap tokens here, verify
                pendingFees += fee;
                unchecked {
                    uint256 toReturn = msg.value - fee;
                    payable(msg.sender).transfer(toReturn);
                }
            } else {
                feeToken.safeTransferFrom(msg.sender, address(this), fee);
                pendingFees += fee;
            }

            //we should always have transferred in the fee at this point, so we can now process the rewards token claim
            comptroller.claimComp(msg.sender);
            return;
        }
    }

    function handleFees() external nonReentrant whenNotPaused {
        //add fee handling logic
    }

    //** ADMIN FUNCTIONS */

    function setComptroller(ComptrollerInterface comptroller_) external onlyOwner {
        require(address(comptroller_) != address(0), "Invalid comptroller");
        //any other comptroller sanity checks?
        comptroller = comptroller_;
        //if the unitroller changes, we want to also make sure we still have the correct oracle
        IBEXAggregator pendingOracle = IBEXAggregator(comptroller.oracle());
        //run some sanity checks here? Get price of protocol token and make sure its not 0?
        oracle = pendingOracle;
        emit ComptrollerSet(address(comptroller_));
        emit OracleSet(address(oracle));
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
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
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
