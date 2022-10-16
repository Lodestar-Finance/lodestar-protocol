// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;


contract MockFlags {
    bool private flag;

    function getFlag(address) external view returns (bool) {
        return flag;
    }

    function setFlag(bool _flag) external {
        flag = _flag;
    }
}