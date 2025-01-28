// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BondingToken} from "./BToken.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract BondingCurve {
    struct LiquidityPool {
        uint256 id;
        address creator;
        address token;
        uint256 virtualReserve;
        uint256 virtualTokenSupply;
        uint256 realReserveBalance;
        uint256 realTokenBalance;
        bool lpCreationStarted;
        bool lpCreated;
        uint256 feePercentage;
        uint256 feeBalance;
        uint256 currentPrice;
    }

    LiquidityPool[] public pools;
    uint256 poolCount;

    address immutable ADMIN_ADDRESS;
    address immutable TREASURY_ADDRESS;

    uint256 constant MIN_RESERVE = 200000000 * 10 ** 18;

    uint256 constant INITIAL_VIRTUAL_RESERVE = 212_118 * 10 ** 18; // 212,118 WAYE (in MIST)
    uint256 constant INITIAL_VIRTUAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1.1 billion tokens in mist
    uint256 constant SETUP_FEE = 1 ether;

    uint256 POOL_FINAL_LISKS_AMOUNT = 366255000000 * 10 ** 18;

    uint256 constant BASIS_POINTS = 10000;

    //uniswap v3
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // Uniswap V3 NonfungiblePositionManager

    IUniswapV3Factory public factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
    INonfungiblePositionManager public positionManager = INonfungiblePositionManager(POSITION_MANAGER);

    error Unauthorized();
    error NotEnoughTokenInVault();
    error InvalidAmount();
    error NotEnoughLiskInVault();
    error SlippageExceeded();
    error PoolNotInitialized();
    error PoolNotSoldOut();
    error PoolClosed();
    error PoolNotClosed();
    error PoolAlreadyPrepared();
    error PoolNotPrepared();
    error AccountNotEmpty();

    event PoolCreated(uint256 poolId, uint256 virtualReserveAmt, uint256 virtualTokenAmt);
    event Buy(uint256 poolId, uint256 virtualReserveAmt, uint256 virtualTokenAmt);
    event BondingCurveFinished(uint256 poolId);

    event PoolCreated(address token0, address token1, uint24 fee, address pool);
    event LiquidityAdded(uint256 tokenId, uint256 liquidity);

    constructor(address ADMIN, address TREASURY) {
        ADMIN_ADDRESS = ADMIN;
        TREASURY_ADDRESS = TREASURY;
    }

    modifier onlyAdmin() {
        require(msg.sender == ADMIN_ADDRESS, "Not admin");
        _;
    }

    function createPool(string memory tokenName, string memory tokenSymbol) external payable returns (uint256) {
        require(msg.value == SETUP_FEE, "setup fee not provided");
        uint256 poolIndex = poolCount;

        BondingToken token = new BondingToken(tokenName, tokenSymbol, address(this));
        uint256 totalSupply = token.totalSupply();

        pools.push(
            LiquidityPool({
                id: poolIndex,
                creator: msg.sender,
                token: address(token),
                virtualReserve: INITIAL_VIRTUAL_RESERVE,
                virtualTokenSupply: INITIAL_VIRTUAL_SUPPLY,
                realReserveBalance: 0,
                realTokenBalance: totalSupply,
                lpCreationStarted: false,
                lpCreated: true,
                feePercentage: 100,
                feeBalance: 0,
                currentPrice: INITIAL_VIRTUAL_RESERVE * BASIS_POINTS / INITIAL_VIRTUAL_SUPPLY
            })
        );

        emit PoolCreated(poolIndex, INITIAL_VIRTUAL_RESERVE, INITIAL_VIRTUAL_SUPPLY);

        poolCount += 1;
        return poolIndex;
    }

    function buyTokens(uint256 poolId, uint256 reserveAmount, uint256 minTokenOut) public payable {
        LiquidityPool memory pool = pools[poolId];
        require(msg.value > 0, "msg value is 0");
        require(reserveAmount > 0, "error Invalid amount");
        require(reserveAmount == msg.value, "error Invalid amount");
        require(!pool.lpCreationStarted, "Already started");

        // handle fees
        uint256 feeAmt = (reserveAmount * pool.feePercentage) / BASIS_POINTS;
        // Need to fix this for the final
        uint256 paymentAfterFee = reserveAmount - feeAmt;

        // Calculate initial tokens to receive
        uint256 tokensOut;

        uint256 initialAmt = calculateOutputTokens(poolId, reserveAmount);
        require(initialAmt >= minTokenOut, "insufficient liq");

        uint256 remainingSupply = pool.realTokenBalance - initialAmt;
        if (remainingSupply < MIN_RESERVE) {
            // calculate how many tokens we can actually buy to the minimum threshold of a pool
            tokensOut = pool.realTokenBalance - MIN_RESERVE;
            //calculate the reserve currency
            uint256 k = INITIAL_VIRTUAL_RESERVE * INITIAL_VIRTUAL_SUPPLY;
            uint256 newTokenSupply = pool.virtualTokenSupply - tokensOut;
            uint256 newReserve = k / newTokenSupply;
            uint256 actualReserveNeeded = newReserve - pool.virtualReserve;

            feeAmt = actualReserveNeeded * pool.feePercentage / BASIS_POINTS;

            // return excess msg.value
            uint256 totalNeeded = actualReserveNeeded + feeAmt;
            uint256 totalExcess = reserveAmount - totalNeeded;
            if (totalExcess > 0) {
                (bool success,) = payable(address(msg.sender)).call{value: totalExcess}("");
                require(success, "transfer failed");
            }

            // // Update virtual reserves with actual amounts
            pool.virtualReserve = pool.virtualReserve + actualReserveNeeded;
            pool.virtualTokenSupply = pool.virtualTokenSupply - tokensOut;
            pool.lpCreationStarted = true;
            emit BondingCurveFinished(poolId);
        } else {
            tokensOut = initialAmt;
            pool.virtualReserve = pool.virtualReserve + paymentAfterFee;
            pool.virtualTokenSupply = pool.virtualTokenSupply - tokensOut;
        }

        //    Update current price
        pool.currentPrice = getTokenPrice(poolId);

        // update real balance
        pool.realReserveBalance = pool.realReserveBalance + reserveAmount;
        pool.realTokenBalance = pool.realTokenBalance - tokensOut;

        // send fee to pool creator
        (bool _success,) = payable(pool.creator).call{value: feeAmt}("");
        require(_success, "transfer failed");

        // send purchased tokens to the user
        BondingToken(pool.token).transfer(msg.sender, tokensOut);
        emit Buy(poolId, pool.virtualReserve, pool.virtualTokenSupply);
    }

    function sellTokens(uint256 poolId, uint256 tokenAmount, uint256 minReserveOut) public {
        LiquidityPool memory pool = pools[poolId];
        require(tokenAmount > 0, "error Invalid amount");
        require(minReserveOut > 0, "error Invalid amount");
        require(!pool.lpCreationStarted, "lp created already");

        // calculate reserve currency to receive - LISK
        uint256 reserveOut = calculateOutputReserve(poolId, tokenAmount);

        // Handle fees
        uint256 feeAmt = (reserveOut * pool.feePercentage) / BASIS_POINTS;
        uint256 reserveAmtAfterFees = reserveOut - feeAmt;

        require(reserveAmtAfterFees >= minReserveOut, "insufficient liquidity");

        // update pool virtual reserves
        pool.virtualReserve = pool.virtualReserve - reserveOut;
        pool.virtualTokenSupply = pool.virtualTokenSupply + tokenAmount;

        // update current price
        pool.currentPrice = getTokenPrice(poolId);
        //update real balances
        pool.realReserveBalance = pool.realReserveBalance - reserveOut;
        pool.realTokenBalance = pool.realTokenBalance + tokenAmount;

        // handle movement of funds
        // user sends the token to the pool
        BondingToken(pool.token).transferFrom(msg.sender, address(this), tokenAmount);

        // pool creator is credited with the sell fee
        // send fee to pool creator
        (bool _success,) = payable(pool.creator).call{value: feeAmt}("");
        require(_success, "transfer failed");
        // sends the LISK (Native token) to user
        (bool success,) = payable(address(msg.sender)).call{value: reserveAmtAfterFees}("");
        require(success, "transfer failed");
    }

    //@todo migrate pool from here to integrated exchange service and close pool
    function migratePool(uint256 poolId) external view {
        LiquidityPool memory pool = pools[poolId];
        require(pool.creator == msg.sender, "Not creator");
        require(!pool.lpCreated, "Already created");
        require(pool.lpCreationStarted, "Not started");
        // uint256 supply = pool.realTokenBalance;
        // uint256 reserve = pool.realReserveBalance;

        pool.lpCreated = true;

        // createPool();
        // addLiquidity();

        // forward balance of pool to the integrated exchange (UNISWAP V2)
    }

    function calculateOutputReserve(uint256 poolId, uint256 tokenAmount) public view returns (uint256) {
        LiquidityPool memory pool = pools[poolId];

        // using the k-constant bonding algorithm
        uint256 k = INITIAL_VIRTUAL_RESERVE * INITIAL_VIRTUAL_SUPPLY;
        uint256 newTokenSupply = pool.virtualTokenSupply + tokenAmount;
        uint256 newReserve = k / newTokenSupply;
        return pool.virtualReserve - newReserve;
    }

    function calculateOutputTokens(uint256 poolId, uint256 reserveAmount) public view returns (uint256) {
        LiquidityPool memory pool = pools[poolId];
        // using the k-constant bonding algorithm
        uint256 k = INITIAL_VIRTUAL_RESERVE * INITIAL_VIRTUAL_SUPPLY;
        uint256 newReserve = pool.virtualReserve + reserveAmount;
        uint256 newTokenSupply = k / newReserve;
        return pool.virtualTokenSupply - newTokenSupply;
    }

    function getPoolCurrentPrice(uint256 poolId) external view returns (uint256) {
        LiquidityPool memory pool = pools[poolId];
        return pool.currentPrice;
    }

    function getTokenPrice(uint256 poolId) public view returns (uint256) {
        LiquidityPool memory pool = pools[poolId];
        uint256 reserve = pool.virtualReserve;

        // Restructured to avoid overflow:
        // First divide reserve by initial reserve to reduce the magnitude
        // Then multiply by the remaining terms
        uint256 scaledReserve = reserve * 1_000_000_000 / INITIAL_VIRTUAL_RESERVE;
        return (scaledReserve * reserve) / INITIAL_VIRTUAL_SUPPLY;
    }

    function createPool(address tokenA, address tokenB, uint24 fee) internal returns (address pool) {
        require(tokenA != tokenB, "Tokens must be different");

        // Sort tokens to match Uniswap standard (token0 < token1)
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // Check if the pool already exists
        address existingPool = factory.getPool(token0, token1, fee);
        if (existingPool != address(0)) {
            return existingPool;
        }

        // Create the new pool
        pool = factory.createPool(token0, token1, fee);
        emit PoolCreated(token0, token1, fee, pool);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint256 amountA,
        uint256 amountB,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 tokenId, uint256 liquidity) {
        require(tokenA != tokenB, "Tokens must be different");

        // Sort tokens to match Uniswap standard (token0 < token1)
        (address token0, address token1, uint256 amount0, uint256 amount1) =
            tokenA < tokenB ? (tokenA, tokenB, amountA, amountB) : (tokenB, tokenA, amountB, amountA);

        // Approve tokens for spending
        IERC20(token0).approve(address(positionManager), amount0);
        IERC20(token1).approve(address(positionManager), amount1);

        // Mint new liquidity position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 300
        });

        (tokenId, , ,  liquidity) = positionManager.mint(params);

        emit LiquidityAdded(tokenId, liquidity);
    }

    //@todo function for pool creators to withdraw fees charged on every buy and sell

    //@todo finalize if admin should pull treasury fee accumulated over time
    // function withdraw_FEE() external {
    //     (bool success,) = TREASURY_ADDRESS.call{value: address(this).balance}("");
    //     require(success, "transfer failed");
    // }
}
