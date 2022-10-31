// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721/ERC721.sol";
import "./ERC721/ERC721Enumerable.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./lib/Strings.sol";

import "./lib/ContentMixin.sol";
import "./lib/NativeMetaTransaction.sol";
import "../libraries/EnumerableSet.sol";

abstract contract ERC721Tradable is ContextMixin, ERC721Enumerable, NativeMetaTransaction, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    event AddMinter(address newMinter);
    event RemoveMinter(address _minter);
    event MintTo(address _to, uint256 _tokenID);

    uint256 _currentTokenId = 0;

    EnumerableSet.AddressSet isMinter;
    
    struct TokenIdInfo {
        uint256 startID;
        uint256 endID;
    }
    
    uint256 public uriID;
    mapping(uint256 => TokenIdInfo) public tokenIdInfo;
    mapping(uint256 => string) public tokenIdURI;
    

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol)  {
        _initializeEIP712(_name);
    }
    
    function getTokenIn(uint256 tokenID) public view returns(uint256) {
        for(uint256 i = 1; i <= uriID; i++) {
            if(tokenID >= tokenIdInfo[i].startID && tokenID <= tokenIdInfo[i].endID) {
                return i;
            }
        }
        return 0;
    }

    function addMinter(address newMinter) onlyOwner public returns(bool) {
        require(!isMinter.contains(newMinter), "has exist");
        isMinter.add(newMinter);
        emit AddMinter(newMinter);
        return true;
    }

    function removeMinter(address _minter) onlyOwner public returns(bool) {
        require(isMinter.contains(_minter), "not exist");
        isMinter.remove(_minter);
        emit RemoveMinter(_minter);
        return true;
    }
    
    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to) public returns(uint256) {
        require(isMinter.contains(msg.sender) || msg.sender == owner(), "not minter");

        uint256 newTokenId = _getNextTokenId();
        
        _mint(_to, newTokenId);
        _incrementTokenId();
        
        emit MintTo(_to, newTokenId);
        return newTokenId;
    }

    function burn(uint256 tokenId) public {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721Burnable: caller is not owner nor approved");
        _burn(tokenId);
    }
    

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    function baseTokenURI() virtual public view returns (string memory);
    
    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        uint256 uID = getTokenIn(_tokenId);
        require(uID != 0, "no uri");
        return string(abi.encodePacked(tokenIdURI[uID], Strings.toString(_tokenId), ".json"));
       //return string(abi.encodePacked(baseTokenURI(), Strings.toString(_tokenId)));
    }

    // function tokenURI(uint256 _tokenId) override public view returns (string memory) {
    //   return string(abi.encodePacked(baseTokenURI(), Strings.toString(_tokenId), ".json"));
    //   //return string(abi.encodePacked(baseTokenURI(), Strings.toString(_tokenId)));
    // }

    address public nftPool;
    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        if (operator == nftPool) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     */
    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }

    function getMinterLength() external view returns(uint256) {
        return isMinter.length();
    }

    function getMinter(uint256 index) external view returns(address) {
        return isMinter.at(index);
    }

    function getContains(address minter) external view returns(bool) {
        return isMinter.contains(minter);
    }

}


contract ERC721Token is ERC721Tradable {
    string private _uri;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    
    constructor(
        string memory uri_,
        string memory _name,
        string memory _symbol,
        address _nftPool

    ) ERC721Tradable(_name, _symbol) {
        _uri = uri_;
        nftPool = _nftPool;
        isMinter.add(_nftPool);
    }
    

    
    function setURI(uint256 num, string memory uri_) external onlyOwner {
        require(num > 0, "num err");
        tokenIdURI[++uriID] = uri_;
        tokenIdInfo[uriID].startID = tokenIdInfo[uriID-1].endID.add(1);
        tokenIdInfo[uriID].endID = tokenIdInfo[uriID-1].endID.add(num);   
    }
    
    function baseTokenURI() override public view returns (string memory) {
        return _uri;
    }

    function getCurrentID() public view returns(uint256) {
        return _currentTokenId;
    }

    function getOwner(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }
}