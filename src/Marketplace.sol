// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";

interface IZangNFT {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
    function exists(uint256 _tokenId) external view returns (bool);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function royaltyInfo(uint256 tokenId, uint256 value) external view returns (address receiver, uint256 royaltyAmount);
    function isApprovedForAll(address account, address operator) external view returns (bool);
}

contract Marketplace is Pausable, Ownable {

    event TokenListed(
        uint256 indexed _tokenId,
        address indexed _seller,
        uint256 amount,
        uint256 _price
    );

    event TokenDelisted(
        uint256 indexed _tokenId
    );

    event TokenPurchased(
        uint256 indexed _tokenId,
        address indexed _buyer,
        address indexed _seller,
        uint256 _amount,
        uint256 _price
    );

    IZangNFT public immutable zangNFTAddress;
    uint16 public platformFeePercentage = 500; //two decimals, so 500 = 5.00%
    address public zangCommissionAccount;

    uint256 public lock = 0;
    uint16 public newPlatformFeePercentage = 0;
    uint256 public constant PLATFORM_FEE_TIMELOCK = 7 days;

    struct Listing {
        uint256 price;
        address seller;
        uint256 amount;
    }

    // (tokenId => (listingId => Listing)) mapping
    mapping(uint256 => mapping(uint256 => Listing)) public listings;
    mapping(uint256 => uint256) public listingCount;

    constructor(IZangNFT _zangNFTAddress, address _zangCommissionAccount) {
        zangNFTAddress = _zangNFTAddress;
        zangCommissionAccount = _zangCommissionAccount;
    }

    function setZangCommissionAccount(address _zangCommissionAccount) public onlyOwner {
        zangCommissionAccount = _zangCommissionAccount;
    }

    function decreasePlatformFeePercentage(uint16 _lowerFeePercentage) public onlyOwner {
        require(_lowerFeePercentage < platformFeePercentage, "Marketplace: _lowerFeePercentage must be lower than the current platform fee percentage");
        platformFeePercentage = _lowerFeePercentage;
    }

    function requestPlatformFeePercentageIncrease(uint16 _higherFeePercentage) public onlyOwner {
        require(_higherFeePercentage > platformFeePercentage, "Marketplace: _higherFeePercentage must be higher than the current platform fee percentage");
        lock = block.timestamp + PLATFORM_FEE_TIMELOCK;
        newPlatformFeePercentage = _higherFeePercentage;
    }

    function applyPlatformFeePercentageIncrease() public onlyOwner {
        require(lock != 0, "Marketplace: platform fee percentage increase must be first requested");
        require(block.timestamp >= lock, "Marketplace: platform fee percentage increase is locked");
        lock = 0;
        platformFeePercentage = newPlatformFeePercentage;
    }

    function listToken(uint256 _tokenId, uint256 _price, uint256 _amount) external whenNotPaused {
        require(zangNFTAddress.exists(_tokenId), "Marketplace: token does not exist");
        require(_amount <= zangNFTAddress.balanceOf(msg.sender, _tokenId), "Marketplace: not enough tokens to list"); // Opt.
        require(_amount > 0, "Marketplace: amount must be greater than 0"); // Opt.
        require(zangNFTAddress.isApprovedForAll(msg.sender, address(this)), "Marketplace: Marketplace contract is not approved");
        require(_price > 0, "Marketplace: price must be greater than 0");

        uint256 listingId = listingCount[_tokenId];
        listings[_tokenId][listingId] = Listing(_price, msg.sender, _amount);
        listingCount[_tokenId]++;
        emit TokenListed(_tokenId, msg.sender, _amount, _price);
    }

    function editListingAmount(uint256 _tokenId, uint256 _listingId, uint256 _amount, uint256 _expectedAmount) external whenNotPaused {
        require(zangNFTAddress.exists(_tokenId), "Marketplace: token does not exist");
        require(_amount <= zangNFTAddress.balanceOf(msg.sender, _tokenId), "Marketplace: not enough tokens to list"); // Opt.
        require(_amount > 0, "Marketplace: amount must be greater than 0"); // Opt.
        require(listings[_tokenId][_listingId].seller != address(0), "Marketplace: listing does not exist"); // Opt.
        require(listings[_tokenId][_listingId].seller == msg.sender, "Marketplace: only seller can edit listing");
        require(listings[_tokenId][_listingId].amount == _expectedAmount, "Marketplace: expected amount does not match");

        listings[_tokenId][_listingId].amount = _amount;
        emit TokenListed(_tokenId, msg.sender, _amount, listings[_tokenId][_listingId].price);
    }
    
    function editListing(uint256 _tokenId, uint256 _listingId, uint256 _price, uint256 _amount, uint256 _expectedAmount) external whenNotPaused {
        require(zangNFTAddress.exists(_tokenId), "Marketplace: token does not exist");
        require(_amount <= zangNFTAddress.balanceOf(msg.sender, _tokenId), "Marketplace: not enough tokens to list"); // Opt.
        require(_amount > 0, "Marketplace: amount must be greater than 0"); // Opt.
        //require(zangNFTAddress.isApprovedForAll(msg.sender, address(this)), "Marketplace: Marketplace contract is not approved");
        require(_price > 0, "Marketplace: price must be greater than 0");
        require(listings[_tokenId][_listingId].seller != address(0), "Marketplace: listing does not exist"); // Opt.
        require(listings[_tokenId][_listingId].seller == msg.sender, "Marketplace: only seller can edit listing");
        require(listings[_tokenId][_listingId].amount == _expectedAmount, "Marketplace: expected amount does not match");

        listings[_tokenId][_listingId] = Listing(_price, msg.sender, _amount);
        emit TokenListed(_tokenId, msg.sender, _amount, _price);
    }

    function editListingPrice(uint256 _tokenId, uint256 _listingId, uint256 _price) external whenNotPaused {
        require(zangNFTAddress.exists(_tokenId), "Marketplace: token does not exist");
        require(_price > 0, "Marketplace: price must be greater than 0");
        require(listings[_tokenId][_listingId].seller != address(0), "Marketplace: listing does not exist"); // Opt.
        require(listings[_tokenId][_listingId].seller == msg.sender, "Marketplace: only seller can edit listing");

        listings[_tokenId][_listingId].price = _price;
        emit TokenListed(_tokenId, msg.sender, listings[_tokenId][_listingId].amount, _price);
    }

    function delistToken(uint256 _tokenId, uint256 _listingId) external whenNotPaused {
        require(_listingId < listingCount[_tokenId], "Marketplace: listing ID out of bounds"); // Opt.
        require(listings[_tokenId][_listingId].seller != address(0), "Marketplace: cannot interact with a delisted listing"); // Opt.
        require(listings[_tokenId][_listingId].seller == msg.sender, "Marketplace: only the seller can delist");

        // We don't check whether the token exists because someone might want to delist a token
        // that has been completely burned

        _delistToken(_tokenId, _listingId);
    }

    function _removeListing(uint256 _tokenId, uint256 _listingId) private {
        delete listings[_tokenId][_listingId];
    }

    function _delistToken(uint256 _tokenId, uint256 _listingId) private {
        _removeListing(_tokenId, _listingId);
        emit TokenDelisted(_tokenId);
    }

    function _handleFunds(uint256 _tokenId, address seller) private {
        uint256 value = msg.value;
        uint256 platformFee = (value * platformFeePercentage) / 10000;

        uint256 remainder = value - platformFee;

        (address creator, uint256 creatorFee) = zangNFTAddress.royaltyInfo(_tokenId, remainder);

        uint256 sellerEarnings = remainder;
        bool sent;

        if(creatorFee > 0) {
            sellerEarnings -= creatorFee;
            (sent, ) = payable(creator).call{value: creatorFee}("");
            require(sent, "Marketplace: could not send creator fee");
        }

        (sent, ) = payable(zangCommissionAccount).call{value: platformFee}("");
        require(sent, "Marketplace: could not send platform fee");

        (sent, ) = payable(seller).call{value: sellerEarnings}("");
        require(sent, "Marketplace: could not send seller earnings");
    }

    function buyToken(uint256 _tokenId, uint256 _listingId, uint256 _amount) external payable whenNotPaused {
        require(_listingId < listingCount[_tokenId], "Marketplace: listing index out of bounds");
        require(listings[_tokenId][_listingId].seller != address(0), "Marketplace: cannot interact with a delisted listing");
        require(listings[_tokenId][_listingId].seller != msg.sender, "Marketplace: cannot buy from yourself");
        require(_amount <= listings[_tokenId][_listingId].amount, "Marketplace: not enough tokens to buy");
        address seller = listings[_tokenId][_listingId].seller;
        // If all copies have been burned, the token is deleted
        require(zangNFTAddress.exists(_tokenId), "Marketplace: token does not exist anymore"); // Opt.
        // If seller transfers tokens "for free", their listing is still active! If they get them back they can still be bought
        require(_amount <= zangNFTAddress.balanceOf(seller, _tokenId), "Marketplace: seller does not have enough tokens anymore");

        uint256 price = listings[_tokenId][_listingId].price;
        // check if listing is satisfied
        require(msg.value == price * _amount, "Marketplace: price does not match");

        // Update listing
        listings[_tokenId][_listingId].amount -= _amount;

        // Delist a listing if all tokens have been sold
        if (listings[_tokenId][_listingId].amount == 0) {
            _delistToken(_tokenId, _listingId);
        }

        emit TokenPurchased(_tokenId, msg.sender, seller, _amount, price);

        _handleFunds(_tokenId, seller);
        zangNFTAddress.safeTransferFrom(seller, msg.sender, _tokenId, _amount, "");
    }
}