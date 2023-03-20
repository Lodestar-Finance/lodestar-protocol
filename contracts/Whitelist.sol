//SPDX-License-Indentifier: MIT

pragma solidity 0.8.10;

import "./OpenZeppelin/Ownable.sol";

contract Whitelist is Ownable {
    mapping(address => bool) private _isWhitelisted;

    constructor() payable { }

    function updateWhitelist(
        address _address,
        bool _isActive
    ) external payable onlyOwner {
        _isWhitelisted[_address] = _isActive;
    }

    function getWhitelisted(address _address) external view returns (bool) {
        return _isWhitelisted[_address];
    }
}
