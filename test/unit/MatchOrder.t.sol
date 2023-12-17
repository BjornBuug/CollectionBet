// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {Base} from "../Base.t.sol";
import {NFTLongShortTrade} from "src/NFTLongShortTrade.sol";
import "forge-std/console2.sol";

/** test unit scenario for Match order.
        Happy Path:
        1. if the seller has enough balance to match the order [x]
        2. if the the protocol admin can withdraw fees once the order is matched [x]
        3. if the seller and buyer are saved correctly [x]
        4. if matchedorder are saved correctly [x]
        5. if the protocol contract received both maker and taker funds once transffered [x]
        6. if the event was emmited [x]
    */


contract TestMatchOrder is Base {
    
    event MatchedOrder(bytes32 hashedOrder, address indexed seller, address indexed buyer,
                     NFTLongShortTrade.Order order);
    event  Deposit(address indexed dst, uint wad);

    function setUp() public {
        
        vm.startPrank(admin);
        // Set the allowed Tokens and nft collection for a specific order
        nftLongShortTrade.setAllowedTokens(address(weth), true);
        nftLongShortTrade.setAllowedCollection(address(mockNFT), true);
        vm.stopPrank();

        // Asign ETH to the buyer and seller
        deal(address(weth), buyer, 1000 ether);
        deal(address(weth), seller, 500 ether);

        // Asign Native eth to the seller 
        deal(address(seller), 1000 ether);
        deal(address(USDC), buyer,  1000 ether);
        deal(address(USDC), seller , 500 ether);

        // Approve the protocol to spend max of tokens on the buyer and seller behalf
        vm.startPrank(buyer);
        weth.approve(address(nftLongShortTrade), type(uint).max);
        USDC.approve(address(nftLongShortTrade), type(uint).max);
        
        vm.startPrank(seller);
        weth.approve(address(nftLongShortTrade), type(uint).max);
        USDC.approve(address(nftLongShortTrade), type(uint).max);

         vm.label(address(weth), "WETH Contract");
         vm.label(address(USDC), "USDC Contract");
    } 


    // 1. Test if the seller has enough balance to match the order?
    function testOrderMatchedWithEnoughWETHBal() public {
        
        // Get the order 
        NFTLongShortTrade.Order memory order = defaultOrder();

        // Sign the order by the bull/maker to get the signature
        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(seller);

        // Let the seller match the order;
        nftLongShortTrade.matchOrder(order, signature);

        // calculate fees to pay based on the required deposit
        uint256 sellerDeposit = order.sellerDeposit * fee / 1000 + order.sellerDeposit;
        uint256 buyerCollateral = order.buyerCollateral * fee / 1000 + order.buyerCollateral;

        uint256 contractBalInWETH = weth.balanceOf(address(nftLongShortTrade));
        emit log_named_decimal_uint("contract Balan in WETH after matched Order", contractBalInWETH, 18);
        emit log_named_decimal_uint("seller + buyer must transffered amount to the contract", sellerDeposit + buyerCollateral, 18);
        assertEq(contractBalInWETH, sellerDeposit + buyerCollateral, "Contract should hold the right amount of WETH");
    }


    // 1. Test that ETH "cannot be send" if WETH is not tokens payment for specific order.
    function test_CannotSendETHIfAllowedTokenIsNotWETH() public {
        
        NFTLongShortTrade.Order memory order = defaultOrder();

        order.paymentAsset = address(USDC);

        console2.log("current payment asset", order.paymentAsset);

        // Sign the order by the bull/maker to get the signature
        bytes memory signature = signOrder(buyerPrivateKey, order);

        // Se the New token for payment is USDC to test if a seller can match an order by send/pay ETH 
        vm.startPrank(admin);
            nftLongShortTrade.setAllowedTokens(address(USDC), true);
        vm.stopPrank();

        vm.startPrank(seller);
        
        uint fee = nftLongShortTrade.fee();

        uint takerPrice = order.sellerDeposit * fee / 1000 + order.sellerDeposit; 
  
        // potential Invariant: the contract must only accept ETH when sending payment directly 
        // to the contract to match order
        vm.expectRevert("INCOMPATIBLE_PAYMENT_ASSET"); // potential Invariant

        console2.log("current payment asset", order.paymentAsset);

        // Send Ether directly when WETH is not the the right tokens payment for this order.(Should revert)
        nftLongShortTrade.matchOrder{ value: takerPrice}(order, signature);
        
    }



    function test_MatchedOrderEventEmitted() public {
    
        NFTLongShortTrade.Order memory order = defaultOrder();

        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        // generate signature
        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.expectEmit(false, true, true, true);

        emit MatchedOrder(hashedOrder, seller, order.maker, order);

        nftLongShortTrade.matchOrder(order, signature);
    }





    // if the the protocol admin can withdraw fees once the order is matched
    function test_WithdrawFeesSaved() public {
        testOrderMatchedWithEnoughWETHBal();

        NFTLongShortTrade.Order memory order = defaultOrder();

        // Calculate the seller and buyer fees
        uint sellerFee = order.sellerDeposit * fee / 1000;
        uint buyerFee = order.buyerCollateral * fee / 1000;
        address token = order.paymentAsset;
        
        uint savedFees = nftLongShortTrade.withdrawableFees(token);

        emit log_named_decimal_uint("Seller Fees", sellerFee , 18);
        emit log_named_decimal_uint("Buyer Fees", buyerFee , 18);

        // Check if the fees are saved once the order is matched
        assertEq(savedFees, sellerFee + buyerFee, "Fees weren't saved");

    }




    function test_OwnerCanWithdrawFees() public {
        test_WithdrawFeesSaved();

        NFTLongShortTrade.Order memory order = defaultOrder();
        address token = order.paymentAsset;
        
        uint withdrawableAmount = nftLongShortTrade.withdrawableFees(token);

        emit log_named_decimal_uint("withdrawableAmount ", withdrawableAmount , 18);

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
    function test_SellerBuyerSaved() public {
        testOrderMatchedWithEnoughWETHBal();
        
        // Get the order to sign
        NFTLongShortTrade.Order memory order = defaultOrder();

        // Hash the order;
        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        // Get the seller address
        address correctSeller = nftLongShortTrade.sellers(uint(hashedOrder));
        address correctBuyer = nftLongShortTrade.buyers(uint(hashedOrder));

        console2.log("current seler address after the matched order", correctSeller);

        // Assert
        assertEq(correctSeller, seller, "Seller address not correct");
        assertEq(correctBuyer, order.maker, "Buyer address not correct");

    }
    


    // if the seller and buyer are saved correctly
    function test_MatchOrderSaved() public {
        testOrderMatchedWithEnoughWETHBal();

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



    // Test if the contract receive the correct amount of tokens from
    // both buyer and seller transffer funds 
    function test_contractBalancePostFeesWithdraw() public {
        test_OwnerCanWithdrawFees();
        
        // Get seller tokens balance in WETH bef
        // Get the buyer tokens balance in WETH bef
        // the amount of both seller and buyer tokens must equal to the contract balance in weth
        NFTLongShortTrade.Order memory order = defaultOrder();
        uint256 sellerDeposit = order.sellerDeposit;
        uint256 buyerCollateral = order.buyerCollateral;

        console2.log("Current Protocol balance", weth.balanceOf(address(nftLongShortTrade)));
        // The contract must hold the sum of sellerDeposit and buyerCollateral after orderMatch
        assertEq(weth.balanceOf(address(nftLongShortTrade)), sellerDeposit + buyerCollateral);

    }


    // @audit seller deposit in ETH in not recorded or hold by the contract.(buyer can be harmed if the seller withdraw transfer their balance to another account)... to investgate more
    function test_WETHDepositWhenETHIsSent() public {

        NFTLongShortTrade.Order memory order = defaultOrder();
        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(seller);

        uint fee = nftLongShortTrade.fee();
        uint sellerDepositInEth = order.sellerDeposit * fee / 1000 + order.sellerDeposit;
        uint256 buyerCollateral = order.buyerCollateral * fee / 1000 + order.buyerCollateral; 

        vm.expectEmit(true, false, false, true);
        emit Deposit(address(nftLongShortTrade), sellerDepositInEth);
        nftLongShortTrade.matchOrder{value : sellerDepositInEth}(order, signature);

        assertEq(weth.balanceOf(address(nftLongShortTrade)), sellerDepositInEth + buyerCollateral);

    }




}


