// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";


contract RegionNFT is ERC721Enumerable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;
    using SafeERC20 for IERC20;
    
    address public admin;
    address public treasury;
    address public questscontract;

    IERC20 public immutable token;

    uint256 public nftMaxSupply = 3000;

    uint256 public totalCrops = 0;
    uint256 public totalFactory = 0;

    uint256 public constant PRICE_KOT = 5000000 * 10 ** 18;
    uint256 public constant PRICE_ETH = 0.02 ether;

    string public baseImageURL;

    event RegionMinted(address indexed owner, uint256 indexed regionId);
    event RegionInitialized(uint256 indexed regionId);
    event TileUpdated(uint256 indexed regionId, uint8 indexed tileId);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event QuestsContractUpdated(address indexed oldQ, address indexed newQ);


    constructor(address _token, address _treasury, address _quest, string memory _baseurl) ERC721 ("Region", "KREGION") {
        admin = msg.sender;
        token = IERC20(_token);
        treasury = _treasury;
        questscontract = _quest;
        baseImageURL = _baseurl;
    }

    modifier onlyQuestsContract() {
        require(msg.sender == questscontract, "Not authorized");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }

    Counters.Counter private _ids;

    struct RegionMeta {
        uint8 pollution;
        uint8 fertility;
        uint8 waterlevel;
        uint8 eco;
        uint256 lastupdate;
    }

    mapping (uint256 => RegionMeta) public regionMeta;

    function claimRegion() external nonReentrant returns (uint256 regionId) {
        require(totalSupply() < nftMaxSupply, "ALL_SOLD");
        token.safeTransferFrom(msg.sender, treasury, PRICE_KOT);
        
        _ids.increment();
        regionId = _ids.current();
        _safeMint(msg.sender, regionId);

        regionMeta[regionId] = RegionMeta({
            pollution: 0,
            fertility: 0,
            waterlevel: 0,
            eco: 0,
            lastupdate: block.timestamp
        });
        initializeRegion(regionId); 

        emit RegionMinted(msg.sender, regionId);     
    }

    function claimWithEth() external payable nonReentrant returns (uint256 regionId) {
        require(totalSupply() < nftMaxSupply, "ALL_SOLD");
        require(msg.value == PRICE_ETH, "INVALID_ETH");

        (bool ok, ) = payable(treasury).call{value: msg.value}("");
        require(ok, "ETH_TRANSFER_FAILED");

        _ids.increment();
        regionId = _ids.current();
        _safeMint(msg.sender, regionId);
        regionMeta[regionId] = RegionMeta({
            pollution: 0,
            fertility: 0,
            waterlevel: 0,
            eco: 0,
            lastupdate: block.timestamp
        });
        initializeRegion(regionId); 
        
        emit RegionMinted(msg.sender, regionId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NON_EXISTING_NFT");
       
        RegionMeta memory meta = regionMeta[tokenId];
        string memory attributes = string (
            abi.encodePacked(
                '[{"trait_type":"Pollution Level","value":', uint256(meta.pollution).toString(),
                '},{"trait_type":"Fertility Index","value":', uint256(meta.fertility).toString(),
                '},{"trait_type":"Water Level","value":', uint256(meta.waterlevel).toString(),
                '},{"trait_type":"Eco Score","value":', uint256(meta.eco).toString(),
                '}]'
            )
        );

        string memory json = string (
            abi.encodePacked(
                '{"name":"Region #', tokenId.toString(),
                '", "description":"Your region in KOTLAND", ',
                '"image":"', baseImageURL, '", ',
                '"attributes":', attributes, '}'
            )
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // function _applyChange(uint8 current, int16 change, uint16 divisor) internal pure returns (uint8) {
    //     int16 inc = int16((( int16(100) - int16(current)) * change) / int16(divisor)) + 1;
    //     int16 temp = int16(current) + inc;

    //     if (temp < 0) return 0;
    //     if (temp > 100) return 100;
    //     return uint8(temp);
    // }

    function _applyChange(uint8 current, int16 change, uint16 divisor) internal pure returns (uint8) {
        int256 curr = int256(uint256(current));
        int256 inc = (((int256(100) - curr) * int256(change)) / int256(uint256(divisor))) + 1;
        int256 temp = curr + inc;

        if (temp < 0) return 0;
        if (temp > 100) return 100;
        return uint8(uint256(temp));
    }


    function _updateRegionMeta(
    uint256 regionId,
    int16 fertChange,
    int16 waterChange,
    int16 pollChange,
    uint16 divisor
) internal {
    RegionMeta storage m = regionMeta[regionId];
    
    m.fertility = _applyChange(m.fertility, fertChange, divisor);
    m.waterlevel = _applyChange(m.waterlevel, waterChange, divisor);
    m.pollution = _applyChange(m.pollution, pollChange, divisor);

    uint16 ecoVal = uint16(100 - m.pollution) + uint16(m.fertility) + uint16(m.waterlevel);
    m.eco = ecoVal > 100 ? 100 : uint8(ecoVal);

    m.lastupdate = block.timestamp;
}

        // new formula
        // inc = floor((100 - curr) * change / D) + 1
        // new = min(100, curr + inc)
    



// function produceFromFactory(uint256 regionId) external {
//     // Increase pollution; slightly reduce fertility and water
//     // pollution +10, fert -3, water -3
//     _updateRegionMeta(regionId, -3, -3, 10, 300);
// }



    struct TileData {
        uint32 id;
        bool isBeingUsed;
        bool isCrop;
        uint8 cropTypeId;
        uint8 factoryTypeId;
        uint8 fertility;
        uint8 waterLevel;
        uint8 growthStage;
    }

    mapping(uint256 => TileData[9]) public regionTiles;
    mapping(uint256 => bool) public regionInitialized;

    modifier onlyRegionOwner(uint256 regionId, address _user) {
        require(ownerOf(regionId) == _user, "NOT_OWNER");
        _;
    }

    function initializeRegion ( uint256 regionId ) internal {
        require(!regionInitialized[regionId], "ALREADY_INITIALIZED");     

        for ( uint8 i = 0; i < 9; ) {
            TileData storage t = regionTiles[regionId][i];
            t.id = i;
            unchecked { i++; }
        }
        regionInitialized[regionId]= true;
        
        emit RegionInitialized(regionId);
    }

    function getTileData(uint256 regionId, uint8 tileIndex) external view returns(
        uint32 id,
        bool isBeingUsed,
        bool isCrop,
        uint8 cropTypeId,
        uint8 factoryTypeId,
        uint8 fertility,
        uint8 waterLevel,
        uint8 growthStage
    ) {
        require(tileIndex < 9, "Invalid tile index");

        TileData memory tile = regionTiles[regionId][tileIndex];

        return (
            tile.id,
            tile.isBeingUsed,
            tile.isCrop,
            tile.cropTypeId,
            tile.factoryTypeId,
            tile.fertility,
            tile.waterLevel,
            tile.growthStage
        );
    }

    function getRegionMeta(uint256 regionId) external view returns (
        uint8 pollution,
        uint8 fertility,
        uint8 waterlevel,
        uint8 eco,
        uint256 lastupdate
    ) {
        RegionMeta memory meta = regionMeta[regionId];
        return (
            meta.pollution,
            meta.fertility,
            meta.waterlevel,
            meta.eco,
            meta.lastupdate
        );
    }


    function setCropOrFactory (bool corf, uint32 tileId, uint8 cofType, address _user, uint256 regionId) external onlyQuestsContract onlyRegionOwner(regionId, _user) {
        TileData storage tile = regionTiles[regionId][tileId];
        if (corf) {
            tile.isBeingUsed = true;
            tile.isCrop = true;
            tile.cropTypeId = cofType;
            totalCrops += 1;
            _updateRegionMeta(regionId, 10, 10, -5, 300);
        } else {
            tile.isBeingUsed = true;
            tile.isCrop = false;
            tile.factoryTypeId = cofType;
            totalFactory += 1;
            _updateRegionMeta(regionId, -7, -7, 15, 300);
        } 
    }

    function updateWFG(uint32 tileId, bool worf, uint8 growth, uint256 regionId, address _user) external onlyQuestsContract onlyRegionOwner(regionId, _user) {
        TileData storage tile = regionTiles[regionId][tileId];
        // true: watering, false: fertilizer
        if (worf) {
            tile.waterLevel += 12;
            _updateRegionMeta(regionId, 5, 15, -5, 300);
        } else {
            tile.fertility += 100;
            _updateRegionMeta(regionId, 15, 0, 0, 300);
        }
        tile.growthStage = growth;
        if (tile.growthStage >= 100) {
            tile.growthStage = 100;
        } 
    }

    function updateAfterHarvest(uint32 tileId, uint256 regionId, address _user) external onlyQuestsContract onlyRegionOwner(regionId, _user) {
        TileData storage tile = regionTiles[regionId][tileId];
        tile.isBeingUsed = false;
        tile.isCrop = false;
        tile.fertility = 0;
        tile.waterLevel = 0;
        tile.factoryTypeId = 0;
        _updateRegionMeta(regionId, 10, 10, 5, 300);
    } 
    
}