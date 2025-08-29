//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Marketplace is Ownable, ReentrancyGuard {
    // constructor () Ownable(msg.sender){}

    enum Status {
        Pending,
        Shipped,
        Delivered,
        Cancelled
    }

    struct Listing {
        uint256 id;
        address payable seller;
        string title;
        uint256 price;
        uint256 stock;
        bool active;
    }

    struct Order {
        uint256 orderId;
        address buyer;
        uint256 listingId;
        uint256 quantity;
        uint256 value;
        Status status;
    }

    uint256 public nextListingId;
    uint256 public nextOrderId;

    uint96 public feeBps;
    address payable treasury;

    mapping(uint256 => Listing) public listings;

    mapping(uint256 => Order) public orders;

    mapping(uint256 => uint256) public orderEscrow;
    mapping(address => uint256) public withdrawable;

    event listingCreated(uint256 id, address indexed seller, string title, uint256 price, uint256 stock);
    event listingUpdated(uint256 id, address indexed seller, string title, bool active);
    event orderPlaced(uint256 orderId, uint256 listingId, address indexed buyer, uint256 value);
    event orderShipped(uint256 orderId);
    event orderDelivered(uint256 orderId, uint256 payout_seller, uint256 fee);
    event orderCancelled(uint256 orderId, address indexed to_buyer, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event feeUpdated(uint96 feeBps, address treasury);

    constructor(uint96 _feeBps, address payable _treasury) Ownable(msg.sender) {
        require(_feeBps <= 1000, "fees are to high");
        require(_treasury != address(0), "_treasury=0");
        feeBps = _feeBps;
        treasury = _treasury;
        emit feeUpdated(feeBps, treasury);
    }

    function setFee(uint96 _feeBps, address payable _treasury) public onlyOwner {
        require(_feeBps <= 1000, "fees are to high");
        require(_treasury != address(0), "_treasury=0");
        feeBps = _feeBps;
        treasury = _treasury;
        emit feeUpdated(feeBps, treasury);
    }

    //Creating Listing

    function createListing(string memory title, uint256 price, uint256 stock) public returns (uint256 id) {
        require(price > 0, "price must be greater than 0");
        require(stock > 0, " stock must be greater than 0");

        nextListingId += 1;
        id = nextListingId;

        Listing memory newListing =
            Listing({id: id, seller: payable(msg.sender), title: title, price: price, stock: stock, active: true});

        listings[id] = newListing;

        emit listingCreated(id, msg.sender, title, price, stock);
    }

    //Updating Listing

    function updatedListing(uint256 id, uint256 newPrice, uint256 newStock, bool active) public {
        Listing storage l = listings[id];
        require(l.seller == msg.sender, "Not Seller");
        require(newPrice > 0, "price must be greater than zero");

        l.price = newPrice;
        l.stock = newStock;
        l.active = active;

        emit listingUpdated(id, msg.sender, l.title, active);
    }

    //Buyer buying products
    function buy(uint256 listingId, uint256 qty) external payable returns (uint256 orderId) {
        Listing storage l = listings[listingId];

        require(l.active, "Inactive");
        require(qty >= 0 && qty < l.stock, "quantity greater than stock");
        uint256 total = l.price * qty;
        require(total == msg.value, "Invalid amount");

        l.stock -= qty;

        nextOrderId += 1;
        orderId = nextOrderId;

        Order memory newOrder = Order({
            orderId: orderId,
            buyer: msg.sender,
            listingId: listingId,
            quantity: qty,
            value: total,
            status: Status.Pending
        });
        orders[orderId] = newOrder;
        orderEscrow[orderId] = total;

        emit orderPlaced(orderId, listingId, msg.sender, total);
    }

    //Order is Shipping
    function shippingOrder(uint256 orderId) public {
        Order storage o = orders[orderId];
        require(o.status == Status.Pending, "status is not pending");

        Listing storage l = listings[o.listingId];
        require(msg.sender == l.seller, "not seller");

        o.status = Status.Shipped;
        emit orderShipped(orderId);
    }

    //confirming delivering the Order
    function confirmDelivery(uint256 orderId) public nonReentrant {
        Order storage o = orders[orderId];
        require(o.status == Status.Shipped, "Item not shipped");
        require(msg.sender == o.buyer, "not buyer");

        o.status = Status.Delivered;
        _releaseFunds(orderId);
    }

    //Cancelling the order Before shipping
    function cancelBeforeShip(uint256 orderId) public nonReentrant {
        Order storage o = orders[orderId];
        require(o.status == Status.Pending, "Order is not in Pending state");

        Listing storage l = listings[o.listingId];
        require(msg.sender == o.buyer || msg.sender == l.seller, "Other can't be cancel the Order");

        l.stock += o.quantity;
        o.status = Status.Cancelled;

        withdrawable[o.buyer] += orderEscrow[orderId];
        orderEscrow[orderId] = 0;

        emit orderCancelled(orderId, o.buyer, o.value);
    }

    function withdraw() public nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "amount greater than zero");

        withdrawable[msg.sender] = 0;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "requires ok");

        emit Withdrawn(msg.sender, amount);
    }

    function _releaseFunds(uint256 orderId) public {
        uint256 val = orderEscrow[orderId];
        Order storage o = orders[orderId];
        Listing storage l = listings[o.listingId];
        require(val > 0, "value must be greater than zero");
        orderEscrow[orderId] = 0;

        uint256 fee = (val * feeBps) / 10000;
        uint256 payout = val - fee;
        withdrawable[l.seller] += payout;
        if (fee > 0) {
            withdrawable[treasury] += fee;
        }
        emit orderDelivered(orderId, payout, fee);
    }
}
