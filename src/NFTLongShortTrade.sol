// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/draft-EIP712.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import {WETH} from "solmate/src/tokens/WETH.sol";



contract NFTLongShortTrade is EIP712("NFTLongShortTrade", "1"), Ownable, ReentrancyGuard, IERC721Receiver {
    
    using SafeERC20 for IERC20;

    //***************************** EVENT ************/
    event MatchedOrder(bytes32 hashedOrder, address indexed seller, address indexed buyer, Order order);
    event AllowCollection(address collection, bool allowed);
    event AllowTokens(address token, bool allowed);
    event UpdateFee(uint16 fee);


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

    uint256 public fee;


    /**
     * @notice Order type hash based on EIP712
     * @dev ORDER_TYPE_HASH ensure that any data being signed match this specific data structure
    */
    bytes32 public constant ORDER_TYPE_HASH = 
            keccak256("Order(uint256 sellerDeposit, uint256 buyerCollateral, uint256 validity, uint256 expiry, uint256 nonce, uint16 fee, address maker, address paymentAsset, address collection, bool isBull)"
    );

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

    /// @notice Keep track of settled contracts
    mapping (uint256 => bool) public setteledContracts;

    /// @notice Keep track of the NFTs the contract holds
    mapping (uint256 => uint256) public claimableTokenId;

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


    // TODO 1-Create a function matchedorder; [x]
    // 2-Hash the order by creating hash order function EIP712 [x]
    // 3- calculate the fee for both sellers and buyers [x]
    // 4- Deteminte who is the maker of the order and who the taker using is Bull/maker [x]
    // 5- Calculate the fee for both maker and taker [x]
    // 6- Storage the value of the buyer and seller in mapping using the contractID/EIP712 hashed order; [x]
    // 7- Retrieve payment based on the the order.asset [x]
    // 8- Create struct to keep track of all the matched order. [x]
    // 9- Check if the signature is valid ??? (Include more conditions to check if the orderisValid); TO BE CONTINUED...
    // 10- Add Functions events 


    /**
     * @notice Match the order with the maker
     * @param order the order created by the maker
     * @param _signature the hashed _signature of the order
     * @return contractId returns the contract id
    */
    function matchOrder(Order calldata order, bytes calldata _signature) external payable nonReentrant returns(uint256) {
            bytes32 hashedOrder = hashOrder(order);

            isValidOrder(order, hashedOrder, _signature);
    
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

            if (takerPrice >= msg.value) {
                require(tokenPayment == weth, "Invalid payment asset");
                WETH(weth).deposit{value : msg.value}();
            } else if(takerPrice > 0 && takerTokensBalance >= takerPrice) {
                IERC20(tokenPayment).safeTransferFrom(msg.sender, address(this), takerPrice);
            } else { revert ERR_NOT_ENOUGH_BALANCE(); } 
        
            emit MatchedOrder(hashedOrder, seller, buyer, order);

        return contractId;
    }


    /** 
      * @notice Hashed the order according to EIP712  
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
      * @notice The NFT seller to settle the contract 
      * @param order the struct order to hash
      * @return tokenId The id of the NFT
    */

    /** Function def: This function would allow the seller of the NFT to settle the contract with the buyer before the expiry of the contract
        Funds transfer: by 1- Send the NFT to the address(this) contract (which would be withdrawble by the Buyer) 
        and secondly transfer the order.sellerDeposit,  order.buyerCollateral to the the the seller.
        State changes: Check if the contract is already settled. Save the NFT into mapping to keep track of the all the NFT hold by the contract
        Sanity checkes: 
        Event Emits: 

                    
    */
    function settleContract(Order memory order, uint256 tokenId) public nonReentrant {
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

            // Send an NFT from seller to the contract to this address(this)
            IERC721(order.collection).safeTransferFrom(seller, address(this), tokenId, data);

            uint256 sellerPayment = order.sellerDeposit + order.buyerCollateral;

            IERC20(order.paymentAsset).safeTransfe(seller, sellerPayment);
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


    // // 
    // function onERC721Received(
    //     address operator, 
    //     address from, 
    //     uint256 tokenId, 
    //     bytes calldata data) external override returns (bytes4) {      
    //     return IERC721Receiver.onERC721Received.selector;
    // } 



}
