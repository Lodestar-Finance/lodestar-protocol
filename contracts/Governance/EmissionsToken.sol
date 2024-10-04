// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract EmissionsToken is ERC20, AccessControl {
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    event Burn(address indexed burner, uint256 amount);
    event BurnerSet(address indexed burner);

    constructor(string memory name, string memory symbol, uint256 totalSupply) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _mint(msg.sender, totalSupply);
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    function setBurner(address burner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BURNER_ROLE, burner);
        emit BurnerSet(burner);
    }
}
