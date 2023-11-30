// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {Base} from "../Base.t.sol";
import {NFTLongShortTrade} from "src/NFTLongShortTrade.sol";
import "forge-std/console2.sol";


/** test unit scenario for Match order.
        Happy Path:
        1. if the seller have enough balance to match the order
        2. if the the protocol admin can withdraw fees once the order is matched
        3. if the seller and buyer are saved correctly
        4. if matchedorder are saved correctly
        5. if the protocol contract received both maker and taker funds once transffered.
        6. if the event was emmited

    */



contract TestMatchOrder is Base {
    

    function setUp() public {

        // Set the allowed Tokens and nft collection for a specific order
        nftLongShortTrade.setAllowedTokens(address(weth), true);
        nftLongShortTrade.setAllowedCollection(address(mockNFT), true);

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
    function testIsSellerHasEnoughBalance() public {
        
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

        console2.log("Fees", sellerFee);
        console2.log("Seller balance", sellerBal);

        assertGe(sellerBal, order.sellerDeposit + sellerFee); // STOPED HERE

    }


    


}


