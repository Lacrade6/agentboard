// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AgentBoard.sol";

/// @notice Minimal mock of the SPACE ID Agent ID contract (ERC-721) for local
///         Foundry tests and BSC testnet ONLY. Mainnet uses the real contract
///         0x60b9262456de011f7d15a54cdd8c48baaa8b022f. NOT for production: anyone
///         can mint here, on purpose, so test workers can hold an Agent ID.
contract MockAgentId is IAgentId {
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _owners;
    uint256 private _nextId = 1;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function balanceOf(address owner) external view override returns (uint256) {
        require(owner != address(0), "zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "nonexistent token");
        return owner;
    }

    function mint(address to) external returns (uint256 tokenId) {
        require(to != address(0), "zero address");
        tokenId = _nextId++;
        _owners[tokenId] = to;
        _balances[to]++;
        emit Transfer(address(0), to, tokenId);
    }
}
