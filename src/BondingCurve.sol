// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BondingToken} from "./BToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IPoolRouter.sol";
import {console} from "forge-std/Test.sol";

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

    address public immutable ADMIN_ADDRESS;
    address public immutable TREASURY_ADDRESS;

    uint256 public constant MIN_RESERVE = 200000000 * 10 ** 18;

    uint256 constant INITIAL_VIRTUAL_RESERVE = 212_118 * 10 ** 18; // 212,118 LISK
    uint256 constant INITIAL_VIRTUAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1.1 billion tokens in LISK
    uint256 public constant SETUP_FEE = 300 * 10 ** 18; // 300 LISK
    address public TOKEN_LISK = 0xac485391EB2d7D88253a7F1eF18C37f4242D1A24;

    uint256 constant BASIS_POINTS = 10000;

    //uniswap v2
    IPoolRouter public velodromeRouter;
    IPoolFactory public velodromeFactory;

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

    constructor(address _router, address _factory, address ADMIN, address TREASURY) {
        ADMIN_ADDRESS = ADMIN;
        TREASURY_ADDRESS = TREASURY;
        velodromeRouter = IPoolRouter(_router);
        velodromeFactory = IPoolFactory(_factory);
    }

    modifier onlyAdmin() {
        require(msg.sender == ADMIN_ADDRESS, "Not admin");
        _;
    }

    function createPool(string memory tokenName, string memory tokenSymbol) external payable returns (uint256) {
        // require(msg.value == SETUP_FEE, "setup fee not provided");
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
                lpCreated: false,
                feePercentage: 100,
                feeBalance: 0,
                currentPrice: INITIAL_VIRTUAL_RESERVE * BASIS_POINTS / INITIAL_VIRTUAL_SUPPLY
            })
        );

        // send setup fee to treasury
        // (bool _success,) = payable(TREASURY_ADDRESS).call{value: msg.value}("");
        // require(_success, "transfer failed");

        // send setup fee to treasury in form of lisk
        IERC20(TOKEN_LISK).transferFrom(msg.sender, TREASURY_ADDRESS, SETUP_FEE);

        emit PoolCreated(poolIndex, INITIAL_VIRTUAL_RESERVE, INITIAL_VIRTUAL_SUPPLY);

        poolCount += 1;
        return poolIndex;
    }

    function buyTokens(uint256 poolId, uint256 reserveAmount, uint256 minTokenOut) public payable {
        LiquidityPool storage pool = pools[poolId];
        // require(msg.value > 0, "msg value is 0");
        require(reserveAmount > 0, "error Invalid amount");
        // require(reserveAmount == msg.value, "error Invalid amount");
        require(!pool.lpCreationStarted, "Already started");

        require(IERC20(TOKEN_LISK).transferFrom(msg.sender, address(this), reserveAmount), "failed to transfer");

        // handle fees
        uint256 feeAmt = (reserveAmount * pool.feePercentage) / BASIS_POINTS;
        // Need to fix this for the final
        uint256 paymentAfterFee = reserveAmount - feeAmt;

        // Calculate initial tokens to receive
        uint256 tokensOut;

        uint256 initialAmtOfTokens = calculateOutputTokens(poolId, reserveAmount);
        require(initialAmtOfTokens >= minTokenOut, "insufficient liq");

        uint256 remainingSupply = pool.realTokenBalance - initialAmtOfTokens;
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
                // (bool success,) = payable(address(msg.sender)).call{value: totalExcess}("");
                // require(success, "transfer failed");
                IERC20(TOKEN_LISK).transfer(msg.sender, totalExcess);
            }
            paymentAfterFee = actualReserveNeeded;

            // // Update virtual reserves with actual amounts
            pool.virtualReserve = pool.virtualReserve + actualReserveNeeded;
            pool.virtualTokenSupply = pool.virtualTokenSupply - tokensOut;
            pool.lpCreationStarted = true;
            emit BondingCurveFinished(poolId);
        } else {
            tokensOut = initialAmtOfTokens;
            pool.virtualReserve = pool.virtualReserve + paymentAfterFee;
            pool.virtualTokenSupply = pool.virtualTokenSupply - tokensOut;
        }

        //    Update current price
        pool.currentPrice = getTokenPrice(poolId);

        // update real balance
        pool.realReserveBalance = pool.realReserveBalance + paymentAfterFee;
        pool.realTokenBalance = pool.realTokenBalance - tokensOut;

        // send fee to pool creator
        // (bool _success,) = payable(pool.creator).call{value: feeAmt}("");
        // require(_success, "transfer failed");
        IERC20(TOKEN_LISK).transfer(pool.creator, feeAmt);

        // send purchased tokens to the user
        BondingToken(pool.token).transfer(msg.sender, tokensOut);
        emit Buy(poolId, pool.virtualReserve, pool.virtualTokenSupply);
    }

    function sellTokens(uint256 poolId, uint256 tokenAmount, uint256 minReserveOut) public {
        LiquidityPool storage pool = pools[poolId];
        require(tokenAmount > 0, "error Invalid amount");
        require(minReserveOut > 0, "error Invalid amount");
        require(!pool.lpCreationStarted, "lp created already");

        // calculate reserve currency to receive - LISK
        uint256 reserveOut = calculateOutputReserve(poolId, tokenAmount);

        // Handle fees
        uint256 feeAmt = (reserveOut * pool.feePercentage) / BASIS_POINTS;
        uint256 reserveAmtAfterFees = reserveOut - feeAmt;

        require(reserveAmtAfterFees >= minReserveOut, "insufficient liquidity");

        // // update pool virtual reserves
        pool.virtualReserve = pool.virtualReserve - reserveOut;
        pool.virtualTokenSupply = pool.virtualTokenSupply + tokenAmount;

        // // update current price
        pool.currentPrice = getTokenPrice(poolId);
        // //update real balances
        pool.realReserveBalance = pool.realReserveBalance - reserveOut;
        pool.realTokenBalance = pool.realTokenBalance + tokenAmount;

        // handle movement of funds
        // user sends the token to the pool
        BondingToken(pool.token).transferFrom(msg.sender, address(this), tokenAmount);

        // send fee to pool creator
        // seller gets their LISK token
        IERC20(TOKEN_LISK).transfer(pool.creator, feeAmt);
        IERC20(TOKEN_LISK).transfer(msg.sender, reserveAmtAfterFees);
    }

    function migratePool(uint256 poolId) external {
        LiquidityPool storage pool = pools[poolId];
        require(pool.creator == msg.sender, "Not creator");
        require(!pool.lpCreated, "Already created");
        require(pool.lpCreationStarted, "Not started");
        uint256 supply = pool.realTokenBalance;
        uint256 reserve = pool.realReserveBalance;

        pool.lpCreated = true;

        // forward balance of pool to the integrated exchange (UNISWAP V2)
        createPoolAndAddLiquidity(pool.token, TOKEN_LISK, supply, reserve);
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

    function createPoolAndAddLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) internal {
        require(amountA > 0 && amountB > 0, "Invalid amounts");

        // Approve Uniswap router to spend the tokens
        IERC20(tokenA).approve(address(velodromeRouter), amountA);
        IERC20(tokenB).approve(address(velodromeRouter), amountB);

        IPoolFactory(velodromeFactory).createPool(tokenA, tokenB, false);

        // Add liquidity to Uniswap V2 (creates the pool if it doesn't exist)
        (,, uint256 liquidity) = velodromeRouter.addLiquidity(
            tokenA,
            tokenB,
            false,
            amountA,
            amountB,
            1, // Min tokenA amount (set to avoid slippage)
            1, // Min tokenB amount (set to avoid slippage)
            msg.sender, // LP tokens receiver
            block.timestamp + 300 // Deadline
        );

        require(liquidity > 0, "Liquidity addition failed");
    }
}
