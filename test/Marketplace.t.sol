//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Marketplace.sol";

contract MarketplaceTest is Test {
    Marketplace public market;
    address seller = address(1);
    address buyer = address(2);
    address treasury = address(3);

    function setUp() public {
        market = new Marketplace(500, payable(treasury));
        vm.deal(seller, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    function testcreateListing() public {
        vm.prank(seller);
        uint256 id = market.createListing("shirt", 1 ether, 10);
        (,, string memory title, uint256 price, uint256 stock, bool active) = market.listings(id);
        assertEq(title, "shirt");
        assertEq(price, 1 ether);
        assertEq(stock, 10);
        assertTrue(active);
    }

    function testbuy() public {
        vm.prank(seller);
        uint256 id = market.createListing("shirt", 1 ether, 10);

        vm.prank(buyer);
        uint256 orderId = market.buy{value: 2 ether}(id, 2);
        (, address _buyer,, uint256 quantity,, Marketplace.Status status) = market.orders(orderId);

        assertEq(quantity, 2);
        assertEq(uint256(status), uint256(Marketplace.Status.Pending));

        assertEq(_buyer, buyer);

        assertEq(market.orderEscrow(orderId), 2 ether);
    }

    function testShipandDelivery() public {
        vm.prank(seller);
        uint256 id = market.createListing("shirt", 1 ether, 5);

        // (,,string memory title,uint256 price,uint256 stock,bool active)=market.listings(id);

        vm.prank(buyer);
        uint256 orderId = market.buy{value: 1 ether}(id, 1);

        // (,address _buyer,,uint256 qty,,Marketplace.Status status)=market.orders(orderId);

        vm.prank(seller);
        market.shippingOrder(orderId);
        (,,,,, Marketplace.Status status) = market.orders(orderId);
        assertEq(uint256(status), uint256(Marketplace.Status.Shipped));

        vm.prank(buyer);
        market.confirmDelivery(orderId);
        (,,,,, Marketplace.Status status2) = market.orders(orderId);
        assertEq(uint256(status2), uint256(Marketplace.Status.Delivered));

        uint256 fee = (1 ether * market.feeBps()) / 10000;
        uint256 payout = 1 ether - fee;
        assertEq(market.withdrawable(seller), payout);
        assertEq(market.withdrawable(treasury), fee);

        uint256 balBefore = seller.balance;
        vm.prank(seller);
        market.withdraw();
        assertEq(seller.balance, balBefore + payout);
    }

    function testCancelBeforeship() public {
        vm.prank(seller);
        uint256 id = market.createListing("shirt", 1 ether, 5);
        (,,,, uint256 stock,) = market.listings(id);

        vm.prank(buyer);
        uint256 orderId = market.buy{value: 1 ether}(id, 1);

        vm.prank(buyer);
        market.cancelBeforeShip(orderId);
        (, address _buyer,,,, Marketplace.Status status) = market.orders(orderId);

        assertEq(stock, 5);
        assertEq(_buyer, buyer);
        assertEq(market.withdrawable(buyer), 1 ether);

        assertEq(market.orderEscrow(orderId), 0);
        assertEq(uint256(status), uint256(Marketplace.Status.Cancelled));

        uint256 preb = buyer.balance;
        vm.prank(buyer);
        market.withdraw();
        uint256 postb = buyer.balance;
        assertEq(postb - preb, 1 ether);
    }

    function testGuards() public {
        vm.prank(seller);
        uint256 id = market.createListing("shirt", 1 ether, 1);

        // we use expectrevert to do next call will fail
        //for wrong ETH
        vm.prank(buyer);
        vm.expectRevert();
        market.buy{value: 2 ether}(id, 1);

        //for more qty

        vm.prank(buyer);
        vm.expectRevert();
        market.buy{value: 2 ether}(id, 2);

        //for Non-sller shipping
        vm.prank(buyer);
        vm.expectRevert();
        market.shippingOrder(id);
    }
}
