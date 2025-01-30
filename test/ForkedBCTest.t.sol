pragma solidity ^0.8.13;

import {BondingToken} from "../src/BToken.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BondingCurveTest is Test {
    BondingCurve public bcContract;
    address admin;
    address treasury;

    address VELODROME_ROUTER = 0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45; // given
    address VELODROME_FACTORY = 0x31832f2a97Fd20664D76Cc421207669b55CE4BC0; // given

    //users
    address user1;
    address user2;

    uint256 constant mint_amount = 1_000_000_000 * 10 ** 18;

    // the identifiers of the forks
    uint256 liskFork;

    string LISK_RPC_URL = vm.envString("LISK_RPC_URL");

    function setUp() public {
        liskFork = vm.createFork(LISK_RPC_URL);
        // select the fork
        vm.selectFork(liskFork);

        admin = makeAddr("ADMIN");
        treasury = makeAddr("TREASURY");
        user1 = makeAddr("USER1");
        user2 = makeAddr("USER2");

        bcContract = new BondingCurve(VELODROME_ROUTER, VELODROME_FACTORY, admin, treasury);

        fund(user1, 1000 ether);
        fund(user2, 1000 ether);
    }

    function testCreatePool() external {
        createPool(user1, "Building", "BDF");
    }

    function testBuyFromPool() external {
        //         create pool
        createPool(user1, "Building", "BDF");
        //         // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        address buyer2 = makeAddr("BUYER-2");
        fund(buyer1, 1000 ether);
        fund(buyer2, 1000 ether);

        buyTokens(buyer1, 600 ether, 0);
        buyTokens(buyer2, 500 ether, 0);
    }

    function testSellIntoPool() external {
        address token;
        address creator;
        uint256 realReserveBalance;
        uint256 realTokenBalance;
        createPool(user1, "Building", "BDF");

        //         // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        fund(buyer1, 1000 ether);
        buyTokens(buyer1, 250 ether, 0);
        (, creator, token,,, realReserveBalance, realTokenBalance,,,,,) = bcContract.pools(0);
        //
        sellTokens(buyer1, IERC20(token).balanceOf(buyer1), 0, token);
    }

    function testMigratePool() external {
        address token;
        address creator;
        uint256 realReserveBalance;
        uint256 realTokenBalance;
        createPool(user1, "Building", "BDF");

        //         // Buy from pool 0
        address buyer1 = makeAddr("BUYER-1");
        fund(buyer1, 10000000 ether);
        buyTokens(buyer1, 10000000 ether, 0);
        (, creator, token,,, realReserveBalance, realTokenBalance,,,,,) = bcContract.pools(0);

        migratePool(user1, 0);
    }

    function createPool(address user, string memory name, string memory symbol) internal {
        vm.startPrank(user);
        IERC20(bcContract.TOKEN_LISK()).approve(address(bcContract), bcContract.SETUP_FEE());
        bcContract.createPool(name, symbol);
        vm.stopPrank();
    }

    function buyTokens(address buyer, uint256 amt, uint256 poolId) internal {
        vm.startPrank(buyer);
        IERC20(bcContract.TOKEN_LISK()).approve(address(bcContract), amt);
        bcContract.buyTokens(poolId, amt, 1);
        vm.stopPrank();
    }

    function sellTokens(address seller, uint256 amt, uint256 poolId, address token) internal {
        vm.startPrank(seller);
        IERC20(token).approve(address(bcContract), amt);

        bcContract.sellTokens(poolId, amt, 1);
        vm.stopPrank();
    }

    function migratePool(address poolCreator, uint256 poolId) internal {
        vm.startPrank(poolCreator);
        bcContract.migratePool(poolId);
        vm.stopPrank();
    }

    function fund(address who, uint256 amount) internal {
        // Prank real holder of LISK token and fund users
        vm.startPrank(0x14fA1c5759f22A5f12322409Ef6847b64041f33a);
        IERC20(bcContract.TOKEN_LISK()).transfer(who, amount);
        vm.stopPrank();
    }
}
