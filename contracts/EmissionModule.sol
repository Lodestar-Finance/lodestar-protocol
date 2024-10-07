//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {StakingRewardsInterface} from "../node_modules/lodestar-helper/contracts/Interfaces/StakingRewardsInterface.sol";
import {WETHUtils} from "../node_modules/lodestar-helper/contracts/Utils/WETHUtils.sol";

import "./util/StorageAccessible.sol";
import "./ComptrollerInterface.sol";
import "./Oracle/Interfaces/IBEXAggregator.sol";
import "./Lens/ILens.sol";
import {EmissionsTokenInterface} from "./Governance/EmissionsTokenInterface.sol";

contract EmissionsModule is Ownable2Step, Pausable, ReentrancyGuard, StorageAccessible {
    using SafeERC20 for IERC20;

    function _msgSender() internal view override returns (address) {
        return super._msgSender();
    }

    function _msgData() internal view override returns (bytes calldata) {
        return super._msgData();
    }

    ComptrollerInterface public comptroller;
    address public emissionsHandler;
    IBEXAggregator public oracle;
    ILens public lens;
    StakingRewardsInterface public stakingRewards;

    uint256 public pendingFees;
    uint256 FEE_PERCENTAGE;

    IERC20 public emissionsToken;
    IERC20 public convertedToken;
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
    event ConvertedTokens(address indexed account, uint256 amount, uint256 fee);
    event FeesHandled(uint256 amount);
    event StakingRewardsSet(address indexed stakingRewards);
    event FeeIsZero(uint256 timestamp);

    //emissions handler intentionally not set in constructor
    constructor(
        ComptrollerInterface comptroller_,
        IBEXAggregator emissionsTokenOracle,
        uint256 feePercentage,
        IERC20 emissionsToken_,
        IERC20 feeToken_,
        address pool_,
        StakingRewardsInterface stakingRewards_
    ) Ownable() {
        comptroller = comptroller_;
        oracle = emissionsTokenOracle;
        FEE_PERCENTAGE = feePercentage;
        emissionsToken = emissionsToken_;
        feeToken = feeToken_;
        pool = pool_;
        stakingRewards = stakingRewards_;
    }

    function getClaimable(address account_) public returns (uint256) {
        bytes memory data = abi.encodeWithSelector(ILens.getPendingRewards.selector, account_);
        bytes memory response = simulate(address(lens), data);
        return abi.decode(response, (uint256));
    }

    function getFee(uint256 amount_) public view returns (uint256) {
        uint256 price = oracle.getPrice(pool);
        //assuming the price is scaled to 18 decimals, we need to scale it back to 18 after multiplying
        return (amount_ * price * FEE_PERCENTAGE) / 1e36;
    }

    function convert(uint256 amount, uint256 lockTime) external payable nonReentrant whenNotPaused {
        require(amount > 0, "amount must not be 0");
        //transfer tokens from user to this contract and burn them
        emissionsToken.safeTransferFrom(msg.sender, address(this), amount);
        emissionsToken.burn(amount);
        if (isExemptFromFees[msg.sender] && lockTime == 0) {
            //this is a whitelisted actor, so we give them the converted tokens directly
            convertedToken.safeTransferFrom(address(this), msg.sender, amount);
            emit ConvertedTokens(msg.sender, amount, 0);
            return;
        } else if (lockTime > 0) {
            //stake the converted tokens on behalf of the user
            //validation checks happen in stakingRewards, lock time must be restricted to 90 or 180 days.
            require(lockTime == 90 days || lockTime == 180 days, "Invalid lock time");
            stakingRewards.stakeLODEBehalf(msg.sender, amount, lockTime);
            emit ConvertedTokens(msg.sender, amount, 0);
            return;
        } else {
            //if user is not exempt from fees and is not staking, we need to take a fee
            uint256 fee = getFee(amount);
            //fee should never be 0. if amount is > 0, if fee = 0 that means the oracle price is 0 and we should emit a log
            if (fee == 0) {
                emit FeeIsZero(block.timestamp);
                revert("Fee is 0");
            }
            if (msg.value > 0) {
                require(msg.value >= fee, "Insufficient funds");
                //if the user wants to pay in native tokens we need to wrap them before anything else
                //TODO:wrap tokens here, verify
                uint256 balanceBefore = address(feeToken).balanceOf(address(this));
                WETHUtils.wrapEther(fee);
                uint256 balanceAfter = address(feeToken).balanceOf(address(this));
                //necessary? put in unchecked?
                require(balanceAfter - balanceBefore == fee, "Incorrect fee amount");
                pendingFees += fee;
                unchecked {
                    //we know that fee < msg.value, so this will not revert
                    uint256 toReturn = msg.value - fee;
                    payable(msg.sender).transfer(toReturn);
                }
                emit ConvertedTokens(msg.sender, amount, fee);
            } else {
                //if they are not paying with native tokens, they must pay with the fee token
                feeToken.safeTransferFrom(msg.sender, address(this), fee);
                pendingFees += fee;
                emit ConvertedTokens(msg.sender, amount, fee);
            }
            return;
        }
    }

    function handleFees() external nonReentrant whenNotPaused {
        //add fee handling logic
        //so, we need to take the current amount of pending fees,
        require(msg.sender == emissionsHandler, "Caller is not the emissions handler");
        uint256 amount = pendingFees;
        if (amount == 0) {
            return;
        }
        pendingFees = 0;
        feeToken.safeTransfer(msg.sender, amount);
        emit FeesHandled(amount);
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

    function setStakingRewards(StakingRewardsInterface stakingRewards_) external onlyOwner {
        require(address(stakingRewards_) != address(0), "Invalid staking rewards");
        stakingRewards = stakingRewards_;
        emit StakingRewardsSet(address(stakingRewards_));
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
