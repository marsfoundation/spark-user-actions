// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

contract VatMock {

    mapping(address => mapping (address => uint256)) public can;

    mapping (address => uint256) public dai;

    function hope(address usr) external {
        can[msg.sender][usr] = 1;
    }

    function move(address src, address dst, uint256 amount) external {
        require(msg.sender == src || can[src][msg.sender] == 1, "Vat/not-allowed");

        dai[src] -= amount;
        dai[dst] += amount;
    }

    function __setDaibalance(address usr, uint256 amount) external {
        dai[usr] = amount;
    }

}
