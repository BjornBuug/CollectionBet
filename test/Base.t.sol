// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "forge-std/Test.sol";

import {MockERC20} from "../mocks/mockERC20.sol";
import {MockERC721} from "../mocks/mockERC721.sol";
import {NFTLongShortTrade} from "../src/NFTLongShortTrade.sol";
import {ERC721TokenReceiver} from "solmate/src/tokens/ERC721.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";


abstract contract Base is Test, ERC721TokenReceiver {

    NFTLongShortTrade internal nftLongShortTrade;
    WETH internal weth;
    MockERC20 internal USDC;
    MockERC721 internal mockNFT;

    uint internal buyerPrivateKey;
    address internal buyer;

    uint internal sellerPrivateKey;
    address internal seller;

    uint internal fee = 20;



    constructor() {
        USDC = new MockERC20("USDC token", "USDC", 6);
        mockNFT = new MockERC721("mockNFT collection", "MNC");
        weth = new WETH();

        nftLongShortTrade = new NFTLongShortTrade(fee, address(weth));

        buyerPrivateKey = uint(0X12345);
        buyer = vm.addr(buyerPrivateKey);
        vm.label(buyer, "Buyer");

        sellerPrivateKey = uint(0X6789);
        seller = vm.addr(sellerPrivateKey);
        vm.label(seller, "Seller");

    }

    // @dev "r" and "s"  big numbers represented by byte32 and they are the output of the cryptographic algorithm when signing a message.
    // @dev "v" known as a recovery id. helps indentify the correct signer's public key.
    function signOrder(uint privateKey, nftLongShortTrade.Order memory order) internal returns(bytes memory) {
            bytes32 hashedOrder =  nftLongShortTrade.hashOrder(order);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashedOrder);
            return abi.encodePacked(v,r,s);
    }


    // @dev "r" and "s"  big numbers represented by byte32 and they are the output of the cryptographic algorithm when signing a message.
    // @dev "v" known as a recovery id. helps indentify the correct signer's public key.
    function signSellOrder(uint privateKey, nftLongShortTrade.SellOrder memory sellOrder) internal returns(bytes memory) {
            bytes32 hashedSellOrder =  nftLongShortTrade.hashSellOrder(sellOrder);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashedSellOrder);
            return abi.encodePacked(v,r,s);
    }

    function signOrderHash(uint privateKey, bytes32 orderHash) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }

    function signHash(uint privateKey, bytes32 _hash) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _hash);
        return abi.encodePacked(r, s, v);
    }


}