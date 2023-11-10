// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/draft-EIP712.sol";

import {ERC721TokenReceiver} from "solmate/src/tokens/ERC721.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";


/**
        Function definition: 
        Function params: 
        Sanity checkes: 
        State changes: 
        Funds transfer: 
        Event Emits: 
        NatSpec:
    */




contract NFTLongShortTrade is EIP712("NFTLongShortTrade", "1"), Ownable, ReentrancyGuard, ERC721TokenReceiver {
    
    using SafeERC20 for IERC20;

    //***************************** EVENT ************/
    event MatchedOrder(bytes32 hashedOrder, address indexed seller, address indexed buyer, Order order);
    event AllowCollection(address collection, bool allowed);
    event AllowTokens(address token, bool allowed);
    event UpdateFee(uint16 fee);
    event ContractSetteled(Order indexed order, bytes32 hashOrder, uint tokenId);
    event ClaimedNFT(bytes32 hashOrder, Order order);
    event ClosedPosition(bytes32 sellOrderHash, SellOrder sellOrder, bytes32 hashedOrder, Order order , address indexed buyer);
    event UpdateMinimumValidNonce(address indexed orderMaker, uint256 minimumNonceOrder);
    event UpdateMinimumValidNonceSell(address indexed orderMaker, uint256 minimumNonceOrderSell);
    event PositionTransferred(bytes32 hashedOrder, address recipient);
    event OrderCanceled(Order order, bytes32 hashedOrder);
    event SellOrderCanceled(SellOrder sellOrder, bytes32 hashedSellOrder);

    //***************************** ERROR ************/
    error ERR_NOT_ENOUGH_BALANCE();

    /**
        * @notice Details of the order.
        * @param sellerDeposit Amount deposited by the seller.
        * @param buyerCollateral Amount deposited by the buyer.
        * @param validity Timestamp representing the validity of the order.
        * @param expiry Timestamp representing the expiry of the order.
        * @param nonce Number used to verify the order's validity and prevent order reuse or duplication.
        * @param fee Fees applied to the order.
        * @param maker Address of the user creating the order.
        * @param paymentAsset Address of the ERC20 asset used for payment to the contract.
        * @param collection Address of the ERC712 collection associated with the order.
        * @param isBull Boolean indicating whether the maker is a "Bull".
    */
    struct Order {
        uint256 sellerDeposit;
        uint256 buyerCollateral; 
        uint256 validity; 
        uint256 expiry;
        uint256 nonce;
        uint16 fee; 
        address maker;
        address paymentAsset;
        address collection; 
        bool isBull;
    }


          // TODO Fix the NatSpec
     /**
        * @notice Details of a sell Order
        * @param orderHash The hashed of the order/contract
        * @param price The minimum amount to buy the position
        * @param start Timestamp when the sell order can be used
        * @param end Timestamp when the sell order cannnot be used
        * @param nonce Number used to verify the sell order's validity and prevent order reuse or duplication.
        * @param paymentAsset Address of the ERC20 asset used to pay the buy the order.
        * @param maker Address of the user creating the sell order.
        * @param whitelist The allowed addresses to buy a sell order, if it empty then anyone 
        * @param isBull Boolean indicating whether the maker is a The "Buyer" or "Seller";
    */
    struct SellOrder {
        bytes32 orderHash; 
        uint256 price; 
        uint256 start; 
        uint256 end; 
        uint256 nonce; 
        address paymentAsset; 
        address maker;
        address[] whitelist; 
        bool isBull; 
    }


    uint256 public fee;


    /**
     * @notice Order type hash based on EIP712
     * @dev ORDER_TYPE_HASH ensure that any data being signed match this specific data structure
    */
    bytes32 public constant ORDER_TYPE_HASH = 
            keccak256("Order(uint256 sellerDeposit, uint256 buyerCollateral, uint256 validity, uint256 expiry, uint256 nonce, uint16 fee, address maker, address paymentAsset, address collection, bool isBull)"
    );


    /**
     * @notice Sell Order type hash based on EIP712
     * @dev SELL_ORDER_TYPE_HASH ensure that any data being signed match this specific data structure
    */
    bytes32 public constant SELL_ORDER_TYPES_HASH = 
    keccak256("SellOrder(bytes32 orderHash, uint256 price, uint256 start, uint256 end, uint256 nonce, address paymentAsset, address maker, address[] whitelist, bool isBull)");

    
    /// @notice The address of an sell order maker => to the valid nonce;  
    mapping (address => uint256) public minimumValidNonceOrderSell;

    /// @notice The address of an order maker => to a valid nonce;
    mapping(address => uint256) public minimumValidNonceOrder;

    /// @notice the amount of fee withdrawble by the owner
    mapping (address => uint256) public withdrawableFees;

    /// @notice Address of the seller for a contract
    mapping (uint256 => address) public sellers;

    /// @notice Address of the buyer for a contract
    mapping (uint256 => address) public buyers;

    /// @notice The address of WETH contract
    address payable public immutable weth;

    /// @notice To keep track of all matched order
    mapping (uint256 => Order) public matchedOrders;

    /// @notice Keep track of sold sell order.
    mapping (bytes32 => SellOrder) public confirmedSellOrder;

    /// @notice Keep track of settled contracts
    mapping (uint256 => bool) public setteledContracts;

    /// @notice Keep track of the NFTs the contract holds
    mapping (uint256 => uint256) public claimableTokenId;

    /// @notice Keep track of the reclaimed NFT from the seller
    mapping (uint256 => bool) public reclaimedNFT;

    /// @notice Keep track cancel Order
    mapping (bytes32 => bool) public canceledOrders;

    /// @notice Keep track cancel sell Order
    mapping (bytes32 => bool) public canceledSellOrders;

    // @notice the addresses of an allowed NFT collection 
    mapping (address => bool) public allowedCollection;

    // @notice the addresses of an allowed ERC20 tokens
    mapping (address => bool) public allowedTokens;

    
    /**
     * @param _fee The initial Fee rate
     * @param _weth The address of WETH contract
    */
    constructor(uint16 _fee, address _weth) {
        weth = payable(_weth);
        setFee(_fee);
    }



    /**
     * @notice Match the order with the maker
     * @param order the order created by the maker
     * @param signature the hashed signature of the order
     * @return contractId returns the contract id
    */
    function matchOrder(Order calldata order, bytes calldata signature) public payable nonReentrant returns(uint256) {
            
            // Hash and return the struct order acording to EIP712 for the signer address to sign with their private keys.
            bytes32 hashedOrder = hashOrder(order);

            isValidOrder(order, hashedOrder, signature);
    
            // contractID to saves buyers and seller to mapping after orderMatch
            uint256 contractId = uint256(hashedOrder);

            uint256 sellerFees;
            uint256 buyerFees;
            
            /// @audit issue Cover Rounding issues
            if(fee > 0) {
                sellerFees = (order.sellerDeposit * fee) / 1000;
                buyerFees = (order.buyerCollateral * fee) / 1000;
                withdrawableFees[order.paymentAsset] += sellerFees + buyerFees; 
            }

            address buyer;
            address seller;

            uint256 makerPrice;
            uint256 takerPrice;

            // Determine who is the maker of the order
            if(order.isBull) {
                buyer = order.maker;
                seller = msg.sender;

                // calculate the price must be deposited by both parties
                makerPrice = order.buyerCollateral + buyerFees;
                takerPrice = order.sellerDeposit + sellerFees;

            } else {

                buyer = msg.sender;
                seller = order.maker;

                // calculate the price must be deposited by both parties
                makerPrice = order.sellerDeposit + sellerFees;
                takerPrice = order.buyerCollateral + buyerFees;
                
            }

            sellers[contractId] = seller;
            buyers[contractId] = buyer;

            matchedOrders[contractId] = order;

            address tokenPayment = order.paymentAsset;

            // Retrieve payment from the the order maker
            uint256 makerTokensBalance = IERC20(tokenPayment).balanceOf(order.maker);

            /// @audit note What if the maker want to deposit their eth 
            if(makerPrice > 0 && makerTokensBalance >= makerPrice) {
                IERC20(tokenPayment).safeTransferFrom(order.maker, address(this), makerPrice);
            } else  { revert ERR_NOT_ENOUGH_BALANCE(); }
             
            // Retrieve payment from the taker
            uint256 takerTokensBalance = IERC20(tokenPayment).balanceOf(msg.sender);

            if (takerPrice == msg.value) {
                require(tokenPayment == weth, "INCOMPATIBLE_PAYMENT_ASSET");
                WETH(weth).deposit{value : msg.value}();
            } else if(takerPrice > 0 && takerTokensBalance >= takerPrice) {
                IERC20(tokenPayment).safeTransferFrom(msg.sender, address(this), takerPrice);
            } else { revert ERR_NOT_ENOUGH_BALANCE(); } 
        
            emit MatchedOrder(hashedOrder, seller, buyer, order);

        return contractId;
    }


    /**
     * @notice Allow users to batch multiple orders
     * @param orders Orders to be batched
     * @param signatures Signatures corresponding to the orders
     * @return contractIds returns the contract IDs
    */ 
    function batchMatchOrder(Order[] calldata orders, bytes[] calldata signatures) external returns(uint[] memory) {

            require(orders.length == signatures.length, "LENGHT_UNMATCHED");

            // Create fixed sized array to store the returns values from each matchOrder inside the loop
            uint[] memory contractIds = new uint[](orders.length);

            for(uint i; i < orders.length; i++) {
                contractIds[i] = matchOrder(orders[i], signatures[i]);
            }

            return contractIds;
        
    }





    /** 
      * @notice Allows the seller to settle their contract with the buyer 
      * @param order The order related to the contract
      * @param tokenId The ID of the NFT to settle the contract
    */
    function settleContract(Order calldata order, uint256 tokenId) public nonReentrant {
            
            bytes32 hashedOrder = hashOrder(order);

            // Get the contract id by using the above hash
            uint256 contractId = uint256(hashedOrder);

            // Retrieve the order related to contractId
            matchedOrders[contractId] = order;

            // Get the seller
            address seller = sellers[contractId];

            require(!setteledContracts[contractId], "CONTRACT_ALREADY_SETTELED");

            require(block.timestamp <= order.expiry, "CONTRACT_EXPIRED");

            require(seller == msg.sender, "UNAUTHORIZED_SELLER");

            setteledContracts[contractId] = true;

            claimableTokenId[contractId] = tokenId;

            // Send an NFT from seller to the contract address(this)
            IERC721(order.collection).safeTransferFrom(seller, address(this), tokenId);

            uint256 sellerPayment = order.sellerDeposit + order.buyerCollateral;

            IERC20(order.paymentAsset).safeTransfer(seller, sellerPayment);

            emit ContractSetteled(order, hashedOrder, tokenId);
    }


    /** 
      * @notice Allows the seller to settle several contracts
      * @param orders The orders from which the contracts would be setteled
      * @param tokensIds The token IDs of the NFTs to be transferred
    */
    function batchSettleContract(Order[] calldata orders, uint[] calldata tokensIds) external {

        require(orders.length == tokensIds.length, "UNMATCHED_SIZE");
        
        for(uint i; i < orders.length; i++) {
            settleContract(orders[i], tokensIds[i]);
        }
    }




    /**
      * @notice Allows the buyer of the NFT to either claim their NFT or, if the contract time has expired, both the seller's deposit and their own deposit.
      * @param order The identifier of the order related to the NFT contract
    */
    function claimNFT(Order calldata order) public nonReentrant {

        bytes32 hashedOrder = hashOrder(order);

        uint256 contractId = uint(hashedOrder);

        matchedOrders[contractId] = order;

        address buyer = buyers[contractId];

        require(buyer == msg.sender, "UNAUTHORIZED_BUYER");

        require(!reclaimedNFT[contractId], "ALREADY_RECLAIMED");

        reclaimedNFT[contractId] = true;

        // Check if the contract is setteled if so we transfer the asset to the buyer 
        if(setteledContracts[contractId]) {
            uint256 tokenId = claimableTokenId[contractId];

            //Transfer the NFT from address(this) to the buyer
            IERC721(order.collection).safeTransferFrom(address(this), buyer , tokenId);
        } else {

        // Check if the contract is expired, if it's means that the seller didn't setlle the contract within the validity time
        // Then we send both the collateral and deposit to the seller.

            require(block.timestamp > order.expiry, "CONTRACT_NOT_EXPIRED");
            uint256 buyerRefund = order.buyerCollateral + order.sellerDeposit;
            IERC20(order.paymentAsset).safeTransfer(buyer, buyerRefund);
        }

        emit ClaimedNFT(hashedOrder, order);
    }



    /**
      * @notice Allow users to claim multiple NFTs
      * @param orders The orders from which the NFTs should be claimed
    */
    function batchClaimNFTs(Order[] calldata orders) external {
        
        for(uint i; i < orders.length; i++) {
            claimNFT(orders[i]);
        }
    }

    

    /**
      * @notice Executes the purchase of a specified sell order position.
      * @param sellOrder The struct representing the sell order being purchased.
      * @param signature The digital signature of the sell order, verifying the caller's intent.
      * @param tipAmount The additional amount offered by the buyer, over the sell order price.
      * @return sellOrderId The unique identifier of the successfully purchased sell order.
    */
    function buyPosition(SellOrder calldata sellOrder, bytes calldata signature, uint256 tipAmount) public payable nonReentrant returns(uint256) {
        
        require(tipAmount >= 0, "TIP_CANNOT_BE_ZERO");

        // Get  the order hash that a Bull or bear want to sell to get the contractId to retrieve data associeted with the order.
        bytes32 orderHash = sellOrder.orderHash;

        // Hash the Sell Order
        bytes32 sellOrderHash = hashSellOrder(sellOrder);

        // Create Ids from the above hashes
        uint256 contractId = uint256(orderHash);

        uint256 sellOrderId = uint256(sellOrderHash);

        Order memory order = matchedOrders[contractId];

        isValidSellOrder(sellOrder, sellOrderHash, order, orderHash, signature);

        // Check if the whitelist is empty then pass, other check if the msg.sender's address is in the whitelist
        require(sellOrder.whitelist.length == 0 || isWhiteListed(sellOrder.whitelist, msg.sender), "CALLER_NOT_WHITELISTED");

        // Add the buyer's address 
        if(sellOrder.isBull) {
            buyers[contractId] = msg.sender;
        } else {
            sellers[contractId] = msg.sender;
        }

        // Save the sell order
        confirmedSellOrder[sellOrderHash] = sellOrder;

        // Transfer asset to the Sell Order maker
        address sellOrderMaker = sellOrder.maker;
        address paymentAsset = sellOrder.paymentAsset;
        uint256 buyerPrice = sellOrder.price + tipAmount;
        uint256 buyerBalance = IERC20(paymentAsset).balanceOf(msg.sender);

        if(msg.value > 0) {
            require(msg.value == buyerPrice, "Not enough funds");
            require(paymentAsset == weth, "INCOMPATIBLE_PAYMENT_ASSET");
            WETH(weth).deposit{value: msg.value}();
            IERC20(weth).safeTransfer(sellOrderMaker, msg.value);

        } else if (buyerBalance >= buyerPrice) {
            IERC20(paymentAsset).safeTransferFrom(msg.sender, sellOrderMaker, buyerPrice);
        } else { revert ERR_NOT_ENOUGH_BALANCE(); }

        return sellOrderId;

        emit ClosedPosition(sellOrderHash, sellOrder, orderHash, order, msg.sender);
    } 

    

    /**
        * @notice Verifies the validity of a sell order against its hash and signature.
        * @param sellOrder sellOrder The sell order struct to be verified.
        * @param sellOrderHash The keccak256 hash of the sell order details.
        * @param order The matched order associated with the sell order.
        * @param orderHash The keccak256 hash of the matched order details.
        * @param signature The digital signature proving the sell order's authenticity.
    */
    function isValidSellOrder(SellOrder calldata sellOrder, bytes32 sellOrderHash, Order memory order, bytes32 orderHash, bytes calldata signature) public view {
        
        require(isValidSignature(sellOrder.maker, sellOrderHash, signature), "INVALIDsignature");

        uint256 contractId = uint256(orderHash);

        if(sellOrder.isBull) {

            require(sellOrder.maker == buyers[contractId], "CALLER_IS_NOT_A_BUYER");
            require(!reclaimedNFT[contractId], "ALREADY_RECLAIMED");

        } else {
            require(sellOrder.maker == sellers[contractId], "MAKER_NOT_SELLER");
            require(block.timestamp < order.expiry, "CONTRACT_EXPIRED");
        }

        // Check if the sell order has already a maker => wasn't sold
        require(confirmedSellOrder[sellOrderHash].maker == address(0), "ORDER_ALREADY_SOLD");

        require(block.timestamp >= sellOrder.start, "SELL_ORDER_DIDN'T_START");

        require(block.timestamp < sellOrder.end, "SELL_ORDER_EXPIRED");

        require(!setteledContracts[contractId], "CONTRACT_ALREADY_SETTELED");

        // Verify if the the payment asset are valid
        require(allowedTokens[sellOrder.paymentAsset], "INVALID_PAYMENTASSET");

        // Check if the sell order is not valid
        require(!canceledSellOrders[sellOrderHash], "ORDER_CANCELED");


        // NOTE
        /// Check that the nonce of the sellOrder is valid
        // This check ensure that the order being submitted hasn't been invalidated by the maker 
        // sellOrder.maker setting new minimium valid nonce.
        require(sellOrder.nonce >= minimumValidNonceOrderSell[sellOrder.maker], "INVALID_NONCE");
        // 20 >= 10 
        // *** Creating nonce attached to each transaction ensure that each order is unique and prevent
        // replays attacks.
        // *** Here the order creator(msg.sender) is saying that all only the order that has nonce greater than 10
        // is valid. and the order I created from 1 to 9 are Invalid.

        
    }



    /**
      * @notice Verifies if the provided buyer's address is included in the whitelist.
      * @param whiteList An array of addresses deemed eligible to buy.
      * @param buyer The address of the potential buyer to check against the whitelist.
      * @return bool True if the buyer is whitelisted, false otherwise.
    */
    function isWhiteListed(address[] memory whiteList, address buyer) public pure returns (bool) {
            for(uint256 i; i < whiteList.length; i++) {
                if(whiteList[i] == buyer) {
                    return true;
                }
            }
        return false;
    }


    /** 
      * @notice Hashed the order according to EIP712(data hashing and signing)
      * @param order the struct order to hash
      * @return hashedOrder EIP721 hash of the order
    */  
    function hashOrder(Order calldata order) public view returns(bytes32) {
        // abi.encode package all the input data with different types(string, uint) into bytes format then
        // hashing using keccak256 to get a unique hash
        bytes32 hashedOrder = keccak256(
                abi.encode(
                    ORDER_TYPE_HASH,
                    order.sellerDeposit,
                    order.buyerCollateral,
                    order.validity,
                    order.expiry,
                    order.nonce,
                    order.fee,
                    order.maker,
                    order.paymentAsset,
                    order.collection,
                    order.isBull
                )
            );
        
        // function returns the hash of the fully encoded EIP712 message for this domain
        return _hashTypedDataV4(hashedOrder);
    }



    /**     
      * @notice Allow a sell order maker to disable an off chain signed order
      * @param sellOrder The sell Order to disable
    */
    function cancelSellOrder(SellOrder calldata sellOrder) external {

            bytes32 hashedSellOrder = hashSellOrder(sellOrder);

            // Check if the caller is the order maker
            require(sellOrder.maker == msg.sender, "UNAUTHORIZD_SIGNER");

            // Check if an already sellOrder has a maker 
            require(confirmedSellOrder[hashedSellOrder].maker == address(0), "ALREADY_SOLD");

            require(!canceledSellOrders[hashedSellOrder], "ALREADY_CANCELED");
            
            canceledSellOrders[hashedSellOrder] = true;

            emit SellOrderCanceled(sellOrder, hashedSellOrder);
    }



    /** 
      * @notice Allows the order maker to disable an off chain signed order.
      * @param order The order to disable
    */ 
    function cancelOrder(Order calldata order) external {

        bytes32 hashedOrder = hashOrder(order);

        require(order.maker == msg.sender, "UNAUTHORIZD_SIGNER");
        
        // Check if the order isn't already cancel
        require(!canceledOrders[hashedOrder], "ALREADY_CANCELED");

        // Check if the order isn't already matched before canceling it
        require(matchedOrders[uint256(hashedOrder)].maker == address(0), "ALREADY_MATCHED");

        canceledOrders[hashedOrder] = true;

        emit OrderCanceled(order, hashedOrder);

    }



    /** 
      * @notice Transfer the position of an order to another address
      * @param order The order from which the position will be transfered
      * @param recipient The address to receive the transferred position
    */  
    function transferPosition(Order calldata order, address recipient) public {
        
        require(recipient != address(0), "INVALID_ADDRESS");

        bytes32 hashedOrder = hashOrder(order);

        uint256 contractId = uint256(hashedOrder);

        if(order.isBull) { 
            // Check if the caller is a the buyer 
            require(buyers[contractId] == msg.sender, "UNAUTHORIZED_CALLER");
            buyers[contractId] = recipient;

        } else {
            // Check if the caller is the seller
            require(sellers[contractId] == msg.sender, "UNAUTHORIZED_CALLER");
            sellers[contractId] = recipient;
        }

        emit PositionTransferred(hashedOrder, recipient);

    } 



    /** 
      * @notice Hashed the sell order according to EIP712(data hashing and signing)
      * @param sellOrder the struct SellOrder to hash
      * @return hashedOrder EIP712 hash of the order
    */  
    function hashSellOrder(SellOrder calldata sellOrder) public view returns(bytes32) {
        // abi.encode package all the input data with different types(string, uint) into bytes format then
        // hashing using keccak256 to get a unique hash
        bytes32 hashedSellOrder = keccak256(
                abi.encode(
                    SELL_ORDER_TYPES_HASH,
                    sellOrder.orderHash,
                    sellOrder.price,
                    sellOrder.start,
                    sellOrder.end,
                    sellOrder.nonce,
                    sellOrder.paymentAsset,
                    sellOrder.maker,
                    keccak256(abi.encodePacked(sellOrder.whitelist)),
                    sellOrder.isBull
                )
            );
        
        // function returns the hash of the fully encoded EIP712 message for this domain
        return _hashTypedDataV4(hashedSellOrder);
    }



    /**
     * @notice Sets new fee rate only by the owner
     * @param _fee The value of the new fee rate
    */
    function setFee(uint16 _fee) public onlyOwner {
        require(_fee < 50, "Fee cannot be more than 5%");
        fee = _fee;
        emit UpdateFee(_fee);
    }

    

    /**
        * @notice Verify if an order is valid 
        * @param order the order to verify
        * @param _signature The signature corresponding to the EIP712 hashed order
    */
    function isValidOrder(Order memory order, bytes32 _orderHash , bytes calldata _signature) public view {
        
        // Verify if the signature of a hashed order was made my the maker
        require(isValidSignature(order.maker, _orderHash, _signature), "INVALID_SIGNATURE");

        // Verify if the order's timestamp is greater than validity
        require(block.timestamp >= order.validity, "EXPIRED_ORDER");

        // Verify if the fee set for an order are valid
        require(order.fee >= fee, "INVALID_FEE");

        // Verify if the order would be expired in the future
        require(order.expiry > order.validity, "INVALID_EXPIRY_TIME");

        // Veirify if the the NFT collection in valid
        require(allowedCollection[order.collection], "INVALID_COLLECTION");

        // Verify if the the payment asset are valid
        require(allowedTokens[order.paymentAsset], "INVALID_PAYMENTASSET");

        // Verify if the current order isn't matched order
        require(matchedOrders[uint256(_orderHash)].maker == address(0), "ORDER_ALREADY_MATCHED");

        // Add more conditions to check the order is valid
        require(order.nonce >= minimumValidNonceOrder[order.maker], "INVALID_NONCE");

         // Check if the order isn't already cancel
        require(!canceledOrders[_orderHash], "ORDER_CANCELED");


    }



    /**
        * @notice Set Minimum nonce for an order sell by an order sell maker
        * @param _minimumValidNonceOrderSell minimum nonce set by the order sell maker
    */
    function setMinimumValidNonceOrderSell(uint256 _minimumValidNonceOrderSell) external {
        
        // Create a mapping address => nonce to keep track of each Order.maker setting invalid orders
        require(_minimumValidNonceOrderSell > minimumValidNonceOrderSell[msg.sender], "NONCE_TO_LOW");

        minimumValidNonceOrderSell[msg.sender] = _minimumValidNonceOrderSell;

        emit UpdateMinimumValidNonceSell(msg.sender, _minimumValidNonceOrderSell);
    }




    /**
        * @notice Set Minimum nonce for an order by an order maker
        * @param _minimumValidNonceOrder minimum order set by the order maker
    */
    function setMinimumValidNonce(uint256 _minimumValidNonceOrder) external {
        
        // Create a mapping address => nonce to keep track of each Order.maker setting invalid orders
        require(_minimumValidNonceOrder > minimumValidNonceOrder[msg.sender], "NONCE_TO_LOW");

        minimumValidNonceOrder[msg.sender] = _minimumValidNonceOrder;

        emit UpdateMinimumValidNonce(msg.sender, _minimumValidNonceOrder);
    }



    /**
        * @notice Set an NFT collection by the owner
        * @param _collection The address of the NFT collection
        * @param _allowed Set to `true` if the collection is allowed, `false` otherwise
    */
     function setAllowedCollection(address _collection, bool _allowed) public onlyOwner {
            allowedCollection[_collection] = _allowed;
            emit AllowCollection(_collection, _allowed);
    }


    /**
        * @notice Set permission for using specific ERC20 tokens as a payment asset by the owner
        * @param _token The addresses of the tokens
        * @param _allowed Set to `true` if the tokens are allowed as a payment asset, `false` otherwise
    */
     function setAllowedTokens(address _token, bool _allowed) public onlyOwner {
            allowedTokens[_token] = _allowed;
            emit AllowTokens(_token, _allowed);
    }

    

    /**
        * @notice Verify if the signature of an order hash was made by `_signer`
        * @param _signer The address of the signer
        * @param _signature The signature corresponding to the EIP712 hashed order
        * @param _orderHash The EIP712 hash of the order
        * @return bool Returns `true` if the signature of the hashed order was made by the address of the `_signer`, otherwise `false`.
    */
    function isValidSignature(address _signer, bytes32 _orderHash, bytes calldata _signature) public pure returns (bool) {
        // ECDSA.recover returns an Ethereum Signed Message created from a hash
          return ECDSA.recover(_orderHash, _signature) == _signer;
    }

    


}
