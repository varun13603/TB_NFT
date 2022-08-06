// SPDX-License-Identifier: The Unlicense
// @Title Tronbies
// @Author Albie Tronstein @ Team JustMoney

pragma solidity ^0.8.0;

interface ORACLE {
    function oracleRandom() external view returns (uint256);
}

interface IKraftly {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external returns (bool);
}

interface IRouter {
    function WBASE() external pure returns(address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns(uint256[] memory amounts);
}

import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";


contract Tronbies is ERC721Enumerable, Ownable {
    using Strings for uint256;

    struct ForSale {
        address seller;
        uint256 price;
        uint256 fee;
        uint256 date;
    }
    struct ForSaleByUser {
        uint256[] forSale;
    }

    IKraftly private oldContract;
    ORACLE private _oracle;
    IRouter private jmSwapRouter;
    string public PROVENANCE = "";
    string public baseURI;
    string private baseExtension = ".json";
    uint256 public minSellPrice = 1000000000; // 1000 TRX
    uint256 public nftPrice = 1000000000; // 1000 TRX
    uint256 public nftBuyFeePercent = 3;
    uint256 public refFeePercent = 3;
    uint256 public discountPercent = 15;
    uint256 public constant maxSupply = 10000;
    uint256 public constant maxMintAmount = 10;
    uint256 [maxSupply] internal indices;
    uint256 [] internal minted;
    uint256 [2][] internal _tokensForSale;
    bool private saleIsActive = false;
    address payable public nftBuyFeeAddress;
    address public tbtToken;
    mapping(uint256 => bool) public isMigrateable;
    mapping(address => bool) public isReferrer;
    mapping(address => address) public referredBy;
    mapping(uint256 => ForSale) private _forSale;
    mapping(address => ForSaleByUser) private _forSaleByUser;

    constructor(string memory _name, string memory _symbol, string memory _initBaseURI, address _oldContract, address _nftBuyFeeAddress, address _oracleAddress, address _tbtToken, address _jmSwapRouter) ERC721(_name, _symbol) {
        _oracle = ORACLE(_oracleAddress);
        setBaseURI(_initBaseURI);
        oldContract = IKraftly(_oldContract);
        nftBuyFeeAddress = payable(_nftBuyFeeAddress);
        tbtToken = _tbtToken;
        jmSwapRouter = IRouter(_jmSwapRouter);
    }

    modifier onlyOwnerOfNFT(uint256 _ID) {
        require(_msgSender() == oldContract.ownerOf(_ID), "NFT: You are not the owner of this NFT ID");
        _;
    }


    //
    //   Internal functions
    //
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function randomIndex() internal returns (uint256) {
        uint256 index = uint256(keccak256(abi.encodePacked(_oracle.oracleRandom(), totalSupply(), msg.sender, block.difficulty, block.timestamp))) % maxSupply;
        if (indices[index] != 0) {
            uint256 arrLen = indices.length;
            uint256 tmpI = index;
            for (uint256 i = index; i < arrLen; i++) {
                if (indices[i] == 0) {
                    index = i;
                    break;
                }
            }
            if (index == tmpI) {
                for (uint256 i = 0; i < arrLen; i++) {
                    if (indices[i] == 0) {
                        index = i;
                        break;
                    }
                }
            }
        }
        indices[index] = index + 1;
        
        return index + 1;
    }



    //
    //   Public functions
    //
    function mintNFT(uint256 _mintAmount, address payable _refAddress) public payable {
        require(_mintAmount > 0, "Must mint at least 1 NFT");
        require(saleIsActive == true, "Not for sale yet!");
        require(_mintAmount <= maxMintAmount, "Can not mint more than 10 NFTs per mint");
        require(msg.value >= (nftPrice * _mintAmount), "Value below price");
        require((totalSupply() + _mintAmount) <= maxSupply, "Not enough tokens available");

        for(uint256 i = 0; i < _mintAmount; i++) {
            uint256 mintIndex = randomIndex();
            if (totalSupply() < maxSupply) {
                _safeMint(msg.sender, mintIndex);
                minted.push(mintIndex);
            }
        }

        if ((referredBy[_msgSender()] != address(0) || isReferrer[_refAddress] == true) && refFeePercent != 0) {
            uint256 refAmount = refFeePercent * (nftPrice * _mintAmount) / 100;
            if (referredBy[_msgSender()] == address(0)) {
                referredBy[_msgSender()] = _refAddress;
            }
            require(payable(referredBy[_msgSender()]).send(refAmount));
        }
    }

    function mintingPriceInTBT() public view returns(uint256) {
        uint256 trxAfterDiscount = ((nftPrice * 100) - (nftPrice * discountPercent)) / 100;
        address[] memory path = new address[](2);
        path[0] = jmSwapRouter.WBASE();
        path[1] = tbtToken;
        uint256[] memory amounts = jmSwapRouter.getAmountsOut(trxAfterDiscount, path);
        require(amounts[1] > 0, "Wrong amount out");
        return amounts[1];
    }

    function mintNFTwithTBT(uint256 _mintAmount, address payable _refAddress) public payable {
        require(_mintAmount > 0, "Must mint at least 1 NFT");
        require(saleIsActive == true, "Not for sale yet!");
        require(_mintAmount <= maxMintAmount, "Can not mint more than 10 NFTs per mint");
        require((totalSupply() + _mintAmount) <= maxSupply, "Not enough tokens available");

        uint256 tbtAmount = mintingPriceInTBT();
        require(IERC20(tbtToken).transferFrom(msg.sender, address(this), (tbtAmount * _mintAmount)), "Failed to transfer TBT from minter, did you approve?"); // transfer TBT from user to this contract

        for(uint256 i = 0; i < _mintAmount; i++) {
            uint256 mintIndex = randomIndex();
            if (totalSupply() < maxSupply) {
                _safeMint(msg.sender, mintIndex);
                minted.push(mintIndex);
            }
        }

        if ((referredBy[_msgSender()] != address(0) || isReferrer[_refAddress] == true) && refFeePercent != 0) {
            uint256 refAmount = refFeePercent * tbtAmount / 100;
            if (referredBy[_msgSender()] == address(0)) {
                referredBy[_msgSender()] = _refAddress;
            }
            require(IERC20(tbtToken).transfer(referredBy[_msgSender()], refAmount));
        }
    }

    function sellNFT(uint256 _tokenId, uint256 _price) public {
        require(_price >= minSellPrice, "You must ask more for the NFT.");
        require(ownerOf(_tokenId) == msg.sender, "You are not the owner of this NFT");

        _forSale[_tokenId].seller = msg.sender;
        _forSale[_tokenId].price = _price;
        _forSale[_tokenId].fee = (_price / 100) * nftBuyFeePercent;
        _forSale[_tokenId].date = block.timestamp;

        _forSaleByUser[msg.sender].forSale.push(_tokenId);
        _tokensForSale.push([_tokenId, (_forSale[_tokenId].price + _forSale[_tokenId].fee)]);

        transferFrom(msg.sender, address(this), _tokenId);
    }

    function cancelSell(uint256 _tokenId) public {
        require(msg.sender != address(0));
        require(_forSale[_tokenId].seller == msg.sender, "You are not the seller of this NFT");

        uint256 _lengthUserSell = _forSaleByUser[_forSale[_tokenId].seller].forSale.length;
        for (uint256 i = 0; i < _lengthUserSell; i++) {
            if (_forSaleByUser[_forSale[_tokenId].seller].forSale[i] == _tokenId) {
                _forSaleByUser[_forSale[_tokenId].seller].forSale[i] = _forSaleByUser[_forSale[_tokenId].seller].forSale[_lengthUserSell - 1];
                _forSaleByUser[_forSale[_tokenId].seller].forSale.pop();
                break;
            }
        }

        delete _forSale[_tokenId];

        uint256 _length = _tokensForSale.length;
        for (uint256 i = 0; i < _length; i++) {
            if (_tokensForSale[i][0] == _tokenId) {
                _tokensForSale[i] = _tokensForSale[_length - 1];
                _tokensForSale.pop();
                break;
            }
        }

        _safeTransfer(address(this), msg.sender, _tokenId, "");
    }

    function buyNFT(uint256 _tokenId) public payable {
        require(_forSale[_tokenId].seller != address(0), "Token is not for sale");
        uint256 price = _forSale[_tokenId].price;
        uint256 fee = _forSale[_tokenId].fee;
        uint256 totalPrice = price + fee;
        require(totalPrice > 0, "Wrong total price");
        require(msg.value == totalPrice, "Not a valid amount of TRX sent");

        uint256 _length = _tokensForSale.length;
        for (uint256 i = 0; i < _length; i++) {
            if (_tokensForSale[i][0] == _tokenId) {
                _tokensForSale[i] = _tokensForSale[_length - 1];
                _tokensForSale.pop();
                break;
            }
        }

        _safeTransfer(address(this), msg.sender, _tokenId, "");
        address sellerAddr = _forSale[_tokenId].seller;
        uint256 _lengthUserSell = _forSaleByUser[_forSale[_tokenId].seller].forSale.length;
        for (uint256 i = 0; i < _lengthUserSell; i++) {
            if (_forSaleByUser[_forSale[_tokenId].seller].forSale[i] == _tokenId) {
                _forSaleByUser[_forSale[_tokenId].seller].forSale[i] = _forSaleByUser[_forSale[_tokenId].seller].forSale[_lengthUserSell - 1];
                _forSaleByUser[_forSale[_tokenId].seller].forSale.pop();
                break;
            }
        }
        delete _forSale[_tokenId];
        require(payable(sellerAddr).send(price));
        require(nftBuyFeeAddress.send(fee));
    }

    function tokensForSale() public view returns (uint256[2][] memory) {
        uint256 saleCount = _tokensForSale.length;
        uint256[2][] memory _tfs = new uint256[2][](saleCount);
        for (uint256 i = 0; i < saleCount; i++) {
            _tfs[i] = _tokensForSale[i];
        }
        return _tfs;
    }

    function tokenSaleInfo(uint256 _tokenId) public view returns (address seller, uint256 price, uint256 fee, uint256 total, uint256 timestamp) {
        require(_forSale[_tokenId].seller != address(0), "Token is not for sale");

        seller = _forSale[_tokenId].seller;
        price = _forSale[_tokenId].price;
        fee = _forSale[_tokenId].fee;
        total = price + fee;
        timestamp = _forSale[_tokenId].date;
    }

    function getUsersNFTs(address _user) public view returns (uint256[] memory) {
        uint256 userTokenCount = balanceOf(_user);
        uint256[] memory tokenIds = new uint256[](userTokenCount);
        for (uint256 i = 0; i < userTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_user, i);
        }
        return tokenIds;
    }

    function getUsersForSaleNFTs(address _user) public view returns (uint256[] memory) {
        return _forSaleByUser[_user].forSale;
    }

    function getMintedNFTs() public view returns (uint256[] memory) {
        uint256 mintedCount = minted.length;
        uint256[] memory mintedTokens = new uint256[](mintedCount);
        for (uint256 i = 0; i < mintedCount; i++) {
            mintedTokens[i] = minted[i];
        }
        return mintedTokens;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)) : "";
    }



    //
    //   Owner only functions
    //
    function toggleSaleActive() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    /*     
    * Set provenance once it's calculated
    */
    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        PROVENANCE = provenanceHash;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setMintingPriceInTRX(uint256 _newMintingPrice) public onlyOwner {
        nftPrice = _newMintingPrice;
    }

    function setDiscountPercentTBTminting(uint256 _newDiscountPercent) public onlyOwner {
        require(_newDiscountPercent <= 100, "Must be set from 0 to 100");
        discountPercent = _newDiscountPercent;
    }

    function setJMSwapRouter(address _newJMSwapRouter) public onlyOwner {
        jmSwapRouter = IRouter(_newJMSwapRouter);
    }

    function setMinSellPrice(uint256 _newMinSellPrice) public onlyOwner {
        require(_newMinSellPrice >= 100000000, "Min sell price is 100 TRX");

        minSellPrice = _newMinSellPrice;
    }

    function setRefFeePercent(uint256 _refFee) public onlyOwner {
        require(_refFee <= 100, "NFT: Not a valid fee, set from 0 to 100");

        refFeePercent = _refFee;
    }

    function setRefferer(address _refAddress) public onlyOwner {
        isReferrer[_refAddress] = true;
    }

    function removeRefferer(address _refAddress) public onlyOwner {
        isReferrer[_refAddress] = false;
    }

    function setMigrateableIDs(uint256[] memory _IDs) public onlyOwner {
        for(uint256 i = 0; i < _IDs.length; i++) {
            isMigrateable[_IDs[i]] = true;
            indices[_IDs[i] - 20000] = _IDs[i] - 19999;
        }
    }

    function migrateOldNFT(uint256 _tokenID) public onlyOwnerOfNFT(_tokenID) {
        require(_tokenID >= 20000 && _tokenID < 30000, "NFT: Not a valid Tronbie ID");
        require(isMigrateable[_tokenID] == true, "NFT: Not migrateable");

        oldContract.transferFrom(_msgSender(), address(this), _tokenID);
        oldContract.burn(_tokenID);

        uint256 tronbieID = _tokenID - 19999;
        _safeMint(_msgSender(), tronbieID);
        minted.push(tronbieID);
        isMigrateable[_tokenID] = false;
    }

    function withdrawTRX(address payable recipient) public onlyOwner {
        require(recipient.send(address(this).balance));
    }

    function withdrawTRC20(address _token, address payable recipient) external onlyOwner returns(bool) {
        require(recipient != address(0), "Cannot withdraw the TRC20 Token balance to the zero address");
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal > 0, "The TRC20 Token balance must be greater than 0");

        return IERC20(_token).transfer(recipient, bal);
    }

    function withdrawTRC10(trcToken _tokenID, address payable recipient) external onlyOwner {
        require(recipient != address(0), "Cannot withdraw the TRC10 Token balance to the zero address");
        uint256 bal = address(this).tokenBalance(_tokenID);
        require(bal > 0, "The TRC10 Token balance must be greater than 0");

        recipient.transferToken(bal, _tokenID);
    }
}
