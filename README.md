# CollectionBet Protocol

## About the Protocol

CollectionBet is a peer-to-peer marketplace that allows traders to buy and sell NFTs with future settlement. The protocol enables users to take long or short positions on NFT collections.

Key features include:

- Bullish traders can place buy orders for future NFT purchases at a discount
- Bearish traders can place sell orders to potentially profit from price decreases
- Uses EIP-712 for secure off-chain order creation
- Peer-to-peer trading without intermediaries

How it works:

1. Bullish traders (Bulls):

   - Place buy orders for any NFT from a specific collection
   - Pay a settlement price (usually discounted from the current floor price)
   - Receive an NFT from the collection before the settlement deadline

2. Bearish traders (Bears):

   - Place sell orders for any NFT from a specific collection
   - Pay a security deposit (premium)
   - Agree to sell an NFT at a predetermined price before the deadline
   - Profit if the collection's floor price decreases
   - Lose their security deposit if they fail to deliver the NFT

3. Off-chain Orders:
   - Users can create off-chain orders using the EIP-712 standard

CollectionBet provides a unique way for traders to speculate on NFT collection prices, offering opportunities for both bullish and bearish market participants.

## Foundry Test

To set up and run tests for CollectionBet:

1. Follow the [instructions](https://book.getfoundry.sh/getting-started/installation.html) to install [Foundry](https://github.com/foundry-rs/foundry).
2. Clone and install dependencies: git submodule update --init --recursive
3. Run the tests: `forge test -vv --match-test test_OrderMatchsWithSufficientWETHBalance --match-contract CollectionBet`

Note: Change the contract and function name to test different parts of the protocol.
