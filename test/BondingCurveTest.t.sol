pragma solidity ^0.8.13;

import {BondingToken} from "../src/BToken.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BondingCurveTest is Test {
    BondingCurve public bcContract;
    address admin;
    address treasury;

    address UNISWAPV2_ROUTER = 0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45;
    address UNISWAPV2_FACTORY = 0x31832f2a97Fd20664D76Cc421207669b55CE4BC0;

    //users
    address user1;
    address user2;

    uint256 constant mint_amount = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        admin = makeAddr("ADMIN");
        treasury = makeAddr("TREASURY");
        user1 = makeAddr("USER1");
        user2 = makeAddr("USER2");

        bcContract = new BondingCurve(UNISWAPV2_ROUTER, UNISWAPV2_FACTORY, admin, treasury);
    }

    function testPublicProps() external {
        assertEq(bcContract.MIN_RESERVE(), 200000000 * 10 ** 18);
    }

    // test that pool is created
    // test that token is minted into the pool vault
    // test that treasury receives SET UP fees.
    function testCreatePool() external {
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        createPool(user1, "Building", "BDF");

        assertEq(bcContract.TREASURY_ADDRESS().balance, 1 ether);
        (, address creator, address token,,,,,,,,,) = bcContract.pools(0);
        assertEq(creator, user1);
        //asset how much of Buidling is in pool
        assertEq(IERC20(token).balanceOf(address(bcContract)), mint_amount);

        createPool(user2, "HeyToken", "HYN");
        assertEq(bcContract.TREASURY_ADDRESS().balance, 2 ether);
        (, address creator2, address token2,,,,,,,,,) = bcContract.pools(1);
        assertEq(creator2, user2);
        assertEq(IERC20(token2).balanceOf(address(bcContract)), mint_amount);
    }

    function testBuyFromPool() external {
        vm.deal(user1, 100 ether);

        createPool(user1, "Building", "BDF");
        assertEq(bcContract.TREASURY_ADDRESS().balance, 1 ether);
        (, address creator, address token,,,,,,,,,) = bcContract.pools(0);
        assertEq(creator, user1);
        //asset how much of Buidling is in pool
        assertEq(IERC20(token).balanceOf(address(bcContract)), mint_amount);

        // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        address buyer2 = makeAddr("BUYER-2");
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        buyTokens(buyer1, 100 ether, 0);
        assertEq(IERC20(token).balanceOf(buyer1), bcContract.calculateOutputTokens(0, 100 ether));

        buyTokens(buyer2, 100 ether, 0);
        assertEq(IERC20(token).balanceOf(buyer2), bcContract.calculateOutputTokens(0, 100 ether));
        console.log(IERC20(token).balanceOf(address(bcContract)));
    }

    function testSellIntoPool() external {
        vm.deal(user1, 100 ether);
        address creator;
        address token;
        uint256 realReserveBalance;
        uint256 realTokenBalance;

        createPool(user1, "Building", "BDF");
        assertEq(bcContract.TREASURY_ADDRESS().balance, 1 ether);
        (, creator,  token,,, realReserveBalance, realTokenBalance,,,,,) = bcContract.pools(0);
        assertEq(creator, user1);
        //asset how much of Buidling is in pool
        assertEq(IERC20(token).balanceOf(address(bcContract)), mint_amount);

        // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        address buyer2 = makeAddr("BUYER-2");
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        buyTokens(buyer1, 100 ether, 0);
        // assertEq(IERC20(token).balanceOf(buyer1), bcContract.calculateOutputTokens(0, 100 ether));

        buyTokens(buyer2, 100 ether, 0);
        // assertEq(IERC20(token).balanceOf(buyer2), bcContract.calculateOutputTokens(0, 100 ether));
     

        (, creator,  token,,, realReserveBalance, realTokenBalance,,,,,) = bcContract.pools(0);

        // buyer2 sells purchased tokens
        sellTokens(buyer2, IERC20(token).balanceOf(buyer2), 0, token);
        console.log("The user balance after sells of all tokens", buyer2.balance);
        console.log("The user balance after sells of all tokens", IERC20(token).balanceOf(buyer2));
    }

    function testOnly80PercentSold() external {
        vm.deal(user1, 100 ether);

        createPool(user1, "Building", "BDF");
        assertEq(bcContract.TREASURY_ADDRESS().balance, 1 ether);
        (, address creator, address token,,,,,,,,,) = bcContract.pools(0);
        assertEq(creator, user1);
        //asset how much of Buidling is in pool
        assertEq(IERC20(token).balanceOf(address(bcContract)), mint_amount);

        // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        vm.deal(buyer1, 1000000 ether);

        buyTokens(buyer1, 1000000 ether, 0);
        assertEq(800000000000000000000000000, IERC20(token).balanceOf(buyer1)); // 80% of tokens sold
        assertEq(200000000000000000000000000, IERC20(token).balanceOf(address(bcContract))); //20% for exchange remains in pool
        // test that refunds is made to the user if excess was provided
        console.log(buyer1.balance);
    }

    function createPool(address user, string memory name, string memory symbol) internal {
        vm.startPrank(user);
        bcContract.createPool{value: 1 ether}(name, symbol);
        vm.stopPrank();
    }

    function buyTokens(address buyer, uint256 amt, uint256 poolId) internal {
        vm.startPrank(buyer);
        bcContract.buyTokens{value: amt}(poolId, amt, 1);
        vm.stopPrank();
    }

    function sellTokens(address seller, uint256 amt, uint256 poolId, address token) internal {
        vm.startPrank(seller);
         IERC20(token).approve(address(bcContract), IERC20(token).balanceOf(seller));

        bcContract.sellTokens(poolId, amt, 1);
        vm.stopPrank();
    }
}
