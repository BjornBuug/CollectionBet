// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {Base} from "../Base.t.sol";
import {NFTLongShortTrade} from "src/NFTLongShortTrade.sol";
import "forge-std/console2.sol";


/** test unit scenario for Match order.
        Happy Path:
        1. if the seller has enough balance to match the order [x]
        2. if the the protocol admin can withdraw fees once the order is matched [x]
        3. if the seller and buyer are saved correctly
        4. if matchedorder are saved correctly
        5. if the protocol contract received both maker and taker funds once transffered.
        6. if the event was emmited

        

    */



contract TestMatchOrder is Base {
    

    function setUp() public {
        
        vm.startPrank(admin);
        // Set the allowed Tokens and nft collection for a specific order
        nftLongShortTrade.setAllowedTokens(address(weth), true);
        nftLongShortTrade.setAllowedCollection(address(mockNFT), true);
        vm.stopPrank();

        // Asign ETH to the buyer and seller
        deal(address(weth), buyer, 1000 ether);
        deal(address(weth), seller, 500 ether);

        // Approve the protocol to spend max of tokens on the buyer and seller behalf
        vm.startPrank(buyer);
        weth.approve(address(nftLongShortTrade), type(uint).max);
        
        vm.startPrank(seller);
        weth.approve(address(nftLongShortTrade), type(uint).max);
    }


    // 1. Test if the seller has enough balance to match the order?
    function testOrderMatchedWithEnoughBalance() public {
        
        // Get the order 
        NFTLongShortTrade.Order memory order = defaultOrder();

        // Sign the order by the bull/maker to get the signature
        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(seller);

        // Let the seller match the order;
        nftLongShortTrade.matchOrder(order, signature);

        // calculate fees to pay based on the required deposit
        uint256 sellerFee = order.sellerDeposit * fee / 1000;

        uint256 sellerBal = weth.balanceOf(seller);


        emit log_named_decimal_uint("Fees", sellerFee , 18);
        emit log_named_decimal_uint("Fees", sellerBal , 18);

        assertGe(sellerBal, order.sellerDeposit + sellerFee); // STOPED HERE

    }



    // if the the protocol admin can withdraw fees once the order is matched
    function testWithdrawFees() public {
        testOrderMatchedWithEnoughBalance();

        NFTLongShortTrade.Order memory order = defaultOrder();

        // Calculate the seller and buyer fees
        uint sellerFee = order.sellerDeposit * fee / 1000;
        uint buyerFee = order.buyerCollateral * fee / 1000;
        address token = order.paymentAsset;

        emit log_named_decimal_uint("Seller Fees", sellerFee , 18);
        emit log_named_decimal_uint("Buyer Fees", buyerFee , 18);

        uint withdrawableAmount = nftLongShortTrade.withdrawableFees(token);

        emit log_named_decimal_uint("withdrawableAmount ", withdrawableAmount , 18);

        // Check if the fees are saved once the order is matched
        assertEq(withdrawableAmount, sellerFee + buyerFee, "Fees weren't saved");

        // Check if the owner can withdraw the fees
        vm.startPrank(admin);

        emit log_named_decimal_uint("Admin balance before",
                                        weth.balanceOf(admin), 18);
        nftLongShortTrade.withdrawFees(order.paymentAsset, address(admin));

        emit log_named_decimal_uint("Admin balance after",
                                    weth.balanceOf(admin), 18);
        vm.stopPrank();

        assertEq(withdrawableAmount, weth.balanceOf(admin),
                        "The admin didn't receive the exact withdrawble amount");
    }



    // if the seller and buyer are saved correctly
    function testSellerBuyerSaved() public {
        testOrderMatchedWithEnoughBalance();

        // Get the order to sign
        NFTLongShortTrade.Order memory order = defaultOrder();

        // Hash the order;
        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        // Get the seller address
        address coreectSeller = nftLongShortTrade.sellers(uint(hashedOrder));
        address correctBuyer = nftLongShortTrade.buyers(uint(hashedOrder));

        // Assert
        assertEq(coreectSeller, seller, "Seller address not correct");
        assertEq(correctBuyer, order.maker, "Buyer address not correct");

    }
    


    // if the seller and buyer are saved correctly
    function testMatchOrderSaved() public {
        testOrderMatchedWithEnoughBalance();

        // Get the order to sign
        NFTLongShortTrade.Order memory order = defaultOrder();

        // Hash the order;
        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        (uint sellerDeposit, uint buyerCollateral, , ,uint nonce
                    ,uint fee, address maker, address paymentAsset
                    ,address collection,) = nftLongShortTrade.matchedOrders(uint(hashedOrder));

        assertEq(sellerDeposit, 100 ether, "Seller's deposit isn't correct");
        assertEq(nonce, 10, "Incorrect saved nonce");
        assertEq(fee, 20, "Incorrect saved Fee");
        assertEq(buyerCollateral, 50 ether, "Buyer's collateral isn't correct");
        assertEq(paymentAsset, address(weth), "Incorrect saved Payment asset");
        assertEq(collection, address(mockNFT), "Incorrect saved collection");
        assertEq(maker, buyer, "Incorrect saved maker");
    }


    




}


