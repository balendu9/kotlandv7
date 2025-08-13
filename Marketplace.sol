// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Users.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Marketplace is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public admin;
    Users public usercontract;
    IERC20 public token;

    uint8 public totalTypes = 9;
    uint256 public kotvalue = 0;
    uint256 public totalassetssold = 0;

    struct MarketListing {
        address seller;
        uint8 resourceType;
        uint32 amount;
        uint256 pricePerUnit;
        bool isActive;
    }

    mapping(uint256 => MarketListing) public marketListing;
    uint256 public nextListingId;

    struct ResourceAnalytics {
        uint64 totalUnitsSold;
        uint256 totalRevenue;
        uint256 averagePrice;
        uint256 lastPrice;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 lastUpdatedTime;
    }
    mapping(uint8 => ResourceAnalytics) public resourceAnalytics;

    struct ListingAnalytics {
        uint64 totalUnitsListed;
        uint256 totalListingValue;
        uint64 totalListings;
        uint256 averageListingPrice;
        uint256 lastUpdatedTime;
    }
    mapping(uint8 => ListingAnalytics) public listingAnalytics;

    struct PricePoint {
        uint256 price;
        uint256 timestamp;
    }
    mapping(uint8 => PricePoint[]) public priceHistory;

    struct DailyPriceSummary {
        uint256 low;
        uint256 high;
        uint256 total;
        uint256 count;
        uint256 average;
    }
    mapping(uint8 => mapping(uint256 => DailyPriceSummary))
        public dailyPriceSummary;

    event ListedResourceForSale(
        address indexed seller,
        uint8 resourceType,
        uint32 amount,
        uint256 pricePerUnit,
        uint256 listingId
    );
    event ProductPurchased(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint8 resourceType,
        uint32 amount,
        uint256 totalPrice
    );
    event ContractsSet(address userContract, address tokenContract);
    event TotalTypesUpdated(uint8 oldTotal, uint8 newTotal);
    event AdminTransferred(address oldAdmin, address newAdmin);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_AUTHORIZED");
        _;
    }

    function setContracts(
        address _usercontract,
        address _token
    ) external onlyAdmin {
        require(_usercontract != address(0), "ZERO_ADDRESS_USERCONTRACT");
        require(_token != address(0), "ZERO_ADDRESS_TOKEN");
        usercontract = Users(_usercontract);
        token = IERC20(_token);
        emit ContractsSet(_usercontract, _token);
    }

    function updatetotaltypes(uint8 _total) external onlyAdmin {
        require(_total > 0, "INVALID_TOTAL_TYPES");
        emit TotalTypesUpdated(totalTypes, _total);
        totalTypes = _total;
    }

    function listResourceForSale(
        uint8 _resourceType,
        uint32 _amount,
        uint256 _pricePerUnit
    ) external {
        require(
            _resourceType > 0 && _resourceType < totalTypes,
            "INVALID_RESOURCE_TYPE"
        );
        require(_amount > 0, "INVALID_AMOUNT");
        uint256 amount = usercontract.getUserInventory(
            msg.sender,
            _resourceType
        );
        require(amount >= _amount, "NOT_ENOUGH_RESOURCES");

        usercontract.updateInventory(msg.sender, _resourceType, _amount, false);

        marketListing[nextListingId] = MarketListing({
            seller: msg.sender,
            resourceType: _resourceType,
            amount: _amount,
            pricePerUnit: _pricePerUnit,
            isActive: true
        });

        ListingAnalytics storage la = listingAnalytics[_resourceType];
        la.totalUnitsListed += _amount;
        la.totalListingValue += (_pricePerUnit * _amount);
        la.totalListings += 1;
        la.lastUpdatedTime = block.timestamp;

        if (la.totalUnitsListed > 0) {
            la.averageListingPrice = la.totalListingValue / la.totalUnitsListed;
        }
        usercontract.updateUserExp(msg.sender, 5);

        emit ListedResourceForSale(
            msg.sender,
            _resourceType,
            _amount,
            _pricePerUnit,
            nextListingId
        );
        nextListingId++;
    }

    function buyListedResource(
        uint256 listingId,
        uint32 buyAmount
    ) external nonReentrant {
        MarketListing storage listing = marketListing[listingId];
        require(listing.isActive, "LISTING_NOT_AVAILABLE");
        require(
            buyAmount > 0 && buyAmount <= listing.amount,
            "INVALID_BUY_AMOUNT"
        );

        uint256 cost = listing.pricePerUnit * buyAmount;
        token.safeTransferFrom(msg.sender, listing.seller, cost);
        usercontract.updateInventory(
            msg.sender,
            listing.resourceType,
            buyAmount,
            true
        );

        kotvalue += cost;
        totalassetssold += buyAmount;
        listing.amount -= buyAmount;

        if (listing.amount == 0) {
            listing.isActive = false;
        }

        ResourceAnalytics storage ra = resourceAnalytics[listing.resourceType];
        ra.totalUnitsSold += buyAmount;
        ra.totalRevenue += cost;
        ra.lastPrice = listing.pricePerUnit;
        ra.lastUpdatedTime = block.timestamp;

        if (ra.minPrice == 0 || listing.pricePerUnit < ra.minPrice) {
            ra.minPrice = listing.pricePerUnit;
        }
        if (listing.pricePerUnit > ra.maxPrice) {
            ra.maxPrice = listing.pricePerUnit;
        }

        if (ra.totalUnitsSold > 0) {
            ra.averagePrice = ra.totalRevenue / ra.totalUnitsSold;
        }

        PricePoint memory point = PricePoint({
            price: listing.pricePerUnit,
            timestamp: block.timestamp
        });

        priceHistory[listing.resourceType].push(point);

        uint256 day = block.timestamp / 1 days;
        DailyPriceSummary storage summary = dailyPriceSummary[
            listing.resourceType
        ][day];

        if (summary.count == 0) {
            summary.low = listing.pricePerUnit;
            summary.high = listing.pricePerUnit;
        } else {
            if (listing.pricePerUnit < summary.low)
                summary.low = listing.pricePerUnit;
            if (listing.pricePerUnit > summary.high)
                summary.high = listing.pricePerUnit;
        }

        summary.total += listing.pricePerUnit;
        summary.count += 1;
        summary.average = summary.total / summary.count;
        usercontract.updateUserExp(msg.sender, 20);
        usercontract.updateUserExp(listing.seller, 17);

        usercontract.recordMarketplacetx(
            msg.sender,
            "Purchase",
            resources[listing.resourceType],
            buyAmount,
            true,
            cost
        );
        usercontract.recordMarketplacetx(
            listing.seller,
            "Sold",
            resources[listing.resourceType],
            buyAmount,
            false,
            cost
        );
        emit ProductPurchased(
            listingId,
            msg.sender,
            listing.seller,
            listing.resourceType,
            buyAmount,
            cost
        );
    }

    string[] public resources = [
        "None",
        "Wheat",
        "Corn",
        "Potato",
        "Carrot",
        "Food",
        "Energy",
        "FactoryGoods",
        "Fertilizer"
    ];

    function getListingAnalytics()
        external
        view
        returns (
            uint8[] memory resourceIds,
            uint64[] memory listedUnits,
            uint256[] memory avgListingPrices,
            uint64[] memory totalListings,
            uint64[] memory soldUnits,
            uint256[] memory avgSoldPrices,
            uint256[] memory totalRevenues,
            uint256[] memory minPrices,
            uint256[] memory maxPrices,
            uint256[] memory lastSoldTimes
        )
    {
        resourceIds = new uint8[](totalTypes);
        listedUnits = new uint64[](totalTypes);
        avgListingPrices = new uint256[](totalTypes);
        totalListings = new uint64[](totalTypes);
        soldUnits = new uint64[](totalTypes);
        avgSoldPrices = new uint256[](totalTypes);
        totalRevenues = new uint256[](totalTypes);
        minPrices = new uint256[](totalTypes);
        maxPrices = new uint256[](totalTypes);
        lastSoldTimes = new uint256[](totalTypes);

        for (uint8 i = 0; i < totalTypes; i++) {
            ListingAnalytics memory la = listingAnalytics[i];
            ResourceAnalytics memory ra = resourceAnalytics[i];

            resourceIds[i] = i;
            listedUnits[i] = la.totalUnitsListed;
            avgListingPrices[i] = la.averageListingPrice;
            totalListings[i] = la.totalListings;

            soldUnits[i] = ra.totalUnitsSold;
            avgSoldPrices[i] = ra.averagePrice;
            totalRevenues[i] = ra.totalRevenue;
            minPrices[i] = ra.minPrice;
            maxPrices[i] = ra.maxPrice;
            lastSoldTimes[i] = ra.lastUpdatedTime;
        }
    }

    function getResourceAnalytics(
        uint8 resourceType
    )
        external
        view
        returns (
            uint64 totalUnitsSold,
            uint256 totalRevenue,
            uint256 averagePrice,
            uint256 lastPrice,
            uint256 minPrice,
            uint256 maxPrice,
            uint256 lastUpdatedTime
        )
    {
        ResourceAnalytics memory analytics = resourceAnalytics[resourceType];
        return (
            analytics.totalUnitsSold,
            analytics.totalRevenue,
            analytics.averagePrice,
            analytics.lastPrice,
            analytics.minPrice,
            analytics.maxPrice,
            analytics.lastUpdatedTime
        );
    }

    function getMarketListing(
        uint256 listingId
    )
        external
        view
        returns (
            address seller,
            uint8 resourceType,
            uint32 amount,
            uint256 pricePerUnit,
            bool isActive
        )
    {
        MarketListing memory listing = marketListing[listingId];
        return (
            listing.seller,
            listing.resourceType,
            listing.amount,
            listing.pricePerUnit,
            listing.isActive
        );
    }

    function getListingsInRange(
        uint256 start
    ) external view returns (MarketListing[] memory) {
        require(start < nextListingId, "Start index out of bounds");

        uint256 available = nextListingId - start;
        uint256 actualCount = available > 20 ? 20 : available;

        MarketListing[] memory listings = new MarketListing[](actualCount);

        for (uint256 i = 0; i < actualCount; i++) {
            listings[i] = marketListing[start + i];
        }

        return listings;
    }
}
