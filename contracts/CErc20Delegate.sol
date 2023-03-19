// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import { CErc20 } from "./CErc20.sol";
import { EIP20Interface } from "./EIP20Interface.sol";
import { CDelegateInterface } from "./CTokenInterfaces.sol";

/**
 * @title Compound's CErc20Delegate Contract
 * @notice CTokens which wrap an EIP-20 underlying and are delegated to
 * @author Compound
 */
contract CErc20Delegate is CErc20, CDelegateInterface {
    /**
     * @notice Construct an empty delegate
     */
    constructor() payable {}

    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes calldata data) external virtual override {
        // Shh -- currently unused
        data;

        // Shh -- we don't ever want this hook to be marked pure
        if (false) {
            implementation = address(0);
        }

        if (msg.sender != admin) revert NotAdmin();
    }

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() external virtual override {
        // Shh -- we don't ever want this hook to be marked pure
        if (false) {
            implementation = address(0);
        }

        if (msg.sender != admin) revert NotAdmin();
    }
}
