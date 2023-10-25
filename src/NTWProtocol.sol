// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/interface/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/ownable/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/draft-EIP712.sol";


contract NTWProtocol is EIP712("NFTugOfWar", "1"), Ownable, ReentrancyGuard {
    

    using SafeERC20 for IERC20;

    /**
        * @notice Details of the order.
        * @param bearDeposit Amount deposited by the bear.
        * @param bullCollateral Amount deposited by the bull.
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
        uint256 bearDeposit;
        uint256 bullCollateral; 
        uint256 validity; 
        uint256 expiry;
        uint256 nonce;
        uint16 fee; 
        address maker;
        address paymentAsset;
        address collection; 
        bool isBull;
    }

}
