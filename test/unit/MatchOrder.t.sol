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
    error ERR_NOT_ENOUGH_BALANCE();

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


    /**
        * @dev Tests if an NFT long-short trade order is successfully matched
                when both the buyer and seller have sufficient WETH balance.
    */
    function test_OrderMatchsWithSufficientWETHBalance() public {
        
        NFTLongShortTrade.Order memory order = defaultOrder();

        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(seller);

        nftLongShortTrade.matchOrder(order, signature);

        // calculate fees to pay based on the required deposit/Collateral
        uint256 sellerDeposit = order.sellerDeposit * fee / 1000 + order.sellerDeposit;
        uint256 buyerCollateral = order.buyerCollateral * fee / 1000 + order.buyerCollateral;

        uint256 contractBalInWETH = weth.balanceOf(address(nftLongShortTrade));
        assertEq(contractBalInWETH, sellerDeposit + buyerCollateral, "Contract should hold the right amount of WETH");
    }

    /**
        * @dev Tests if the transaction reverts when a seller attempts
                 to match an order without sufficient WETH balance.
    */
    function test_revertWhenSellerLacksBalance() public {
        
        NFTLongShortTrade.Order memory order = defaultOrder();

        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(seller);

        // Asign only 4 ETH to the seller who matched the order
        deal(address(weth), seller, 4 ether);

        // uint256 sellerDeposit = order.sellerDeposit * fee / 1000 + order.sellerDeposit;

        vm.expectRevert(ERR_NOT_ENOUGH_BALANCE.selector);

        nftLongShortTrade.matchOrder(order, signature);
        
    }

    /**
        * @dev Tests if the transaction reverts when a buyer attempts 
                to match an order without sufficient WETH balance.
    */
    function test_revertWhenBuyerLacksBalance() public {
       
        NFTLongShortTrade.Order memory order = defaultOrder();

        bytes memory signature = signOrder(buyerPrivateKey, order);

        vm.startPrank(buyer);

        deal(address(weth), buyer, 4 ether);

        // uint256 sellerDeposit = order.sellerDeposit * fee / 1000 + order.sellerDeposit;

        vm.expectRevert(ERR_NOT_ENOUGH_BALANCE.selector);

        nftLongShortTrade.matchOrder(order, signature);
        
    }


    /**
        * @dev Tests that ETH transfers are rejected for orders 
                where the specified payment asset is not WETH.
    */
    function test_CannotSendETHIfAllowedTokenIsNotWETH() public {
        
        NFTLongShortTrade.Order memory order = defaultOrder();

        order.paymentAsset = address(USDC);


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

        // Send Ether directly when WETH is not the the right tokens payment for this order(USDC in this case)(Should revert)
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





    /**
        * @dev Tests that the accumulated fees are saved after
                 an order is successfully matched.
    */
    function test_WithdrawFeesSaved() public {
        test_OrderMatchsWithSufficientWETHBalance();

        NFTLongShortTrade.Order memory order = defaultOrder();

        // Calculate the seller and buyer fees
        uint sellerFee = order.sellerDeposit * fee / 1000;
        uint buyerFee = order.buyerCollateral * fee / 1000;
        address token = order.paymentAsset;
        
        uint savedFees = nftLongShortTrade.withdrawableFees(token);

        // Check if the fees are saved once the order is matched
        assertEq(savedFees, sellerFee + buyerFee, "Fees weren't saved");

    }



    /**
        * @dev Tests that the protocol admin can withdraw accumulated 
                fees after an order is successfully matched.
    */
    function test_OwnerCanWithdrawFees() public {
        test_WithdrawFeesSaved();

        NFTLongShortTrade.Order memory order = defaultOrder();
        address token = order.paymentAsset;
        
        uint withdrawableAmount = nftLongShortTrade.withdrawableFees(token);

        vm.startPrank(admin);

        nftLongShortTrade.withdrawFees(order.paymentAsset, address(admin));

        vm.stopPrank();

        assertEq(withdrawableAmount, weth.balanceOf(admin),
                        "The admin didn't receive the exact withdrawble amount");
    }



    /**
        * @dev Tests that the contract correctly records the seller and buyer addresses
                 after an order is successfully matched
    */
    function test_SellerBuyerSaved() public {
        test_OrderMatchsWithSufficientWETHBalance();
    
        NFTLongShortTrade.Order memory order = defaultOrder();

        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        address correctSeller = nftLongShortTrade.sellers(uint(hashedOrder));
        address correctBuyer = nftLongShortTrade.buyers(uint(hashedOrder));

        // Assert
        assertEq(correctSeller, seller, "Incorrect Seller Address");
        assertEq(correctBuyer, order.maker, "Incorrect Buyer Address");

    }
    

    /**
        * @dev Tests that all components of a matched order are correctly saved in the contract.
        * Verifies seller's deposit, buyer's collateral, nonce, fee, payment asset, collection, and maker address.
    */
    function test_MatchOrderStructSaved() public {
        test_OrderMatchsWithSufficientWETHBalance();

        // Get the order to sign
        NFTLongShortTrade.Order memory order = defaultOrder();
        
        // Hash the order;
        bytes32 hashedOrder = nftLongShortTrade.hashOrder(order);

        (uint sellerDeposit, uint buyerCollateral, , ,uint nonce
                    ,uint fee, address maker, address paymentAsset
                    ,address collection,) = nftLongShortTrade.matchedOrders(uint(hashedOrder));

        assertEq(sellerDeposit, 100 ether, "Seller deposit mismatch");
        assertEq(nonce, 10, "Nonce mismatch");
        assertEq(fee, 20, "Fee mismatch");
        assertEq(buyerCollateral, 50 ether, "Buyer collateral mismatch");
        assertEq(paymentAsset, address(weth), "Payment asset mismatch");
        assertEq(collection, address(mockNFT), "Collection mismatch");
        assertEq(maker, buyer, "Maker address mismatch");
    }



    /**
        * @dev Tests that the contract's balance is correctly updated after withdrawing fees.
    */
    function test_contractBalancePostFeesWithdraw() public {
        test_OwnerCanWithdrawFees();
        
        NFTLongShortTrade.Order memory order = defaultOrder();
        uint256 sellerDeposit = order.sellerDeposit;
        uint256 buyerCollateral = order.buyerCollateral;

        assertEq(weth.balanceOf(address(nftLongShortTrade)), sellerDeposit + buyerCollateral);

    }


    /**
        * @dev Tests when ETH is sent, an equivalent amount of WETH is correctly deposited.
    */
    function test_WETHDepositedWhenETHIsSent() public {

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


