// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "forge-std/Test.sol";

import {MockERC20} from "../mocks/mockERC20.sol";
import {MockERC721} from "../mocks/mockERC721.sol";
import {CollectionBet} from "../src/CollectionBet.sol";
import {ERC721TokenReceiver} from "solmate/src/tokens/ERC721.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

abstract contract Base is Test, ERC721TokenReceiver {
    CollectionBet internal collectionBet;
    WETH internal weth;
    MockERC20 internal USDC;
    MockERC721 internal mockNFT;

    uint internal buyerPrivateKey;
    address internal buyer;

    uint internal sellerPrivateKey;
    address internal seller;

    address internal admin;

    // 20 represets 2% in decimals we divide it by 100
    uint16 internal fee = 20;

    constructor() {
        uint adminPrivateKey = uint(0x5555);
        admin = vm.addr(adminPrivateKey);
        vm.label(admin, "Admin");

        vm.startPrank(admin);
        USDC = new MockERC20("USDC token", "USDC", 6);
        mockNFT = new MockERC721("mockNFT collection", "MNC");
        weth = new WETH();

        vm.label(address(weth), "WETH Contract");
        vm.label(address(USDC), "USDC Contract");

        collectionBet = new CollectionBet(fee, address(weth));

        vm.stopPrank();

        buyerPrivateKey = uint(0x12345);
        buyer = vm.addr(buyerPrivateKey);
        vm.label(buyer, "Buyer");

        sellerPrivateKey = uint(0x6789);
        seller = vm.addr(sellerPrivateKey);
        vm.label(seller, "Seller");
    }

    // @dev "r" and "s"  big numbers represented by byte32 and they are the output of the cryptographic algorithm when signing a message.
    // @dev "v" known as a recovery id. helps indentify the correct signer's public key.
    function signOrder(
        uint privateKey,
        CollectionBet.Order memory order
    ) internal returns (bytes memory) {
        bytes32 orderHash = collectionBet.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }

    // @dev "r" and "s"  big numbers represented by byte32 and they are the output of the cryptographic algorithm when signing a message.
    // @dev "v" known as a recovery id. helps indentify the correct signer's public key.
    function signSellOrder(
        uint privateKey,
        CollectionBet.SellOrder memory sellOrder
    ) internal returns (bytes memory) {
        bytes32 hashedSellOrder = collectionBet.hashSellOrder(sellOrder);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashedSellOrder);
        return abi.encodePacked(r, s, v);
    }

    function signOrderHash(
        uint privateKey,
        bytes32 orderHash
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, orderHash);
        return abi.encodePacked(r, s, v);
    }

    function signHash(
        uint privateKey,
        bytes32 _hash
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _hash);
        return abi.encodePacked(r, s, v);
    }

    function defaultOrder() internal view returns (CollectionBet.Order memory) {
        return
            CollectionBet.Order({
                sellerDeposit: 100 ether,
                buyerCollateral: 50 ether,
                validity: block.timestamp + 1 hours,
                expiry: block.timestamp + 3 days,
                nonce: 10,
                fee: fee,
                maker: buyer,
                paymentAsset: address(weth),
                collection: address(mockNFT),
                isBull: true
            });
    }
}
