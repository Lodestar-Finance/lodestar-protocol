// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

contract Timelock {
    error NotAdmin();
    error ExceedMinimumDelay();
    error ExceedMaximumDelay();
    error SenderNotTimelock();
    error NotPendingAdmin();
    error EstimatedExecutionWrong();
    error TransactionNotQueued();
    error TransactionNotSurpassed();
    error TransactionStale();
    error TransactionExecutionReverted();

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint indexed newDelay);
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature,  bytes data, uint eta);
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature,  bytes data, uint eta);
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint value, string signature, bytes data, uint eta);

    uint public constant GRACE_PERIOD = 14 days;
    uint public constant MINIMUM_DELAY = 2 days;
    uint public constant MAXIMUM_DELAY = 30 days;

    address public admin;
    address public pendingAdmin;
    uint public delay;

    mapping (bytes32 => bool) public queuedTransactions;


    constructor(address admin_, uint delay_) payable {
        if (delay_ < MINIMUM_DELAY) revert ExceedMinimumDelay();
        if (delay_ > MAXIMUM_DELAY) revert ExceedMaximumDelay();

        admin = admin_;
        delay = delay_;
    }

    fallback() external payable { }

    function setDelay(uint delay_) external {
        if (msg.sender != address(this)) revert SenderNotTimelock();
        if (delay_ < MINIMUM_DELAY) revert ExceedMinimumDelay();
        if (delay_ > MAXIMUM_DELAY) revert ExceedMaximumDelay();
        delay = delay_;

        emit NewDelay(delay_);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        admin = msg.sender;
        pendingAdmin = address(0);

        emit NewAdmin(msg.sender);
    }

    function setPendingAdmin(address pendingAdmin_) external {
        if (msg.sender != address(this)) revert SenderNotTimelock();
        pendingAdmin = pendingAdmin_;

        emit NewPendingAdmin(pendingAdmin_);
    }

    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32) {
        if (msg.sender != admin) revert NotAdmin();
        if (eta < getBlockTimestamp() + delay) revert EstimatedExecutionWrong();

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external {
        if (msg.sender != admin) revert NotAdmin();

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory) {
        if (msg.sender != admin) revert NotAdmin();

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) revert TransactionNotQueued();
        if (getBlockTimestamp() < eta) revert TransactionNotSurpassed();
        if (getBlockTimestamp() > eta + GRACE_PERIOD) revert TransactionStale();

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) revert TransactionExecutionReverted();

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    function getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }
}
