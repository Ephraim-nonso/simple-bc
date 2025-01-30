## Simple Constant Product Bonding Curve Contract

**A simple constant product bonding curve maintains a fixed product of token reserves, ensuring a continuous supply-demand relationship. As users buy, prices increase; as they sell, prices decrease. Governed by x * y = k, it ensures automatic price discovery and liquidity without external market makers.**

BondingCurve consists of the following functions:

-   **createPool**: Pay setup fee to provide token details to create new pool of your token.
-   **buyTokens**: Buy tokens from the pool. Provide pool id, reserve amount and min amount out.
-   **sellTokens**: Sell tokens back to the token pool. Provide pool id, token amount and min amount out of reserve.
-   **migratePool**: Creator migrate the MIN_RESERVE_AMOUNT and LISK to the Velodrome exchange
-   **calculateOutputReserve**: Get reserve amount out given a pool id and token amount
-   **calculateOutputTokens**: Get tokens amount out given a pool id and reserve amount
-   **getPoolCurrentPrice**: Get the current price of the pool token
-   **getTokenPrice**: Get token price
-   **createPoolAndAddLiquidity**: Internal function to create pool on velodrome and migrate tokens



## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy

Add script file and setup to deploy.

```shell
$ forge script script/BondingCurve.s.sol:BondingCurveScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

```md
For testing purposes only. This contract requires much more test to make production-ready.
```
