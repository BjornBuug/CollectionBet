// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {ERC721} from "solmate/src/tokens/ERC721.sol";


contract MockERC721 is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function mint(address recipient, uint256 id) public {
        _safeMint(recipient, id);
    }

    function tokenURI(uint) public pure override returns(string memory) {
        return "mockNFT";
    }
}