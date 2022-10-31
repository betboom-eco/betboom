// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../common/Op.sol";
import "../../libraries/Address.sol";
import "../../interfaces/IExp.sol";
import "../../interfaces/INFTPool.sol";
import "../../libraries/EnumerableSet.sol";
import "../../types/ReentrancyGuard.sol";

contract PlayerNFT is Op, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet notClaim;
    EnumerableSet.UintSet haveClaim;

    event CastNFT(
        address user, 
        uint256 vipNFT, 
        uint256 newTokenID, 
        uint256 lAmount,
        uint256 bAmount,
        uint256 timeCast
    );

    event ClaimNFT(address user, uint256 tokenID);

    IERC20 public LET;
    IERC20 public BET;
    IExp public expAddress;
    INFTPool public nftPool;
    uint256 public r1Rate = 1000;
    uint256 public r2Rate = 200;
    uint256 public rID;
    bool public isCanCast;

    struct NFTInfo {
        uint256 castNum;
        uint256 r1TokenID;
        uint256 r2TokenID;
        uint256 amount;
        uint256 r1Amount;
        uint256 r2Amount;
        uint256 lUserAmount; 
        uint256 llUserAmount;
        uint256 notClaim; 
        uint256 haveClaim;
    }

    struct CastInfo {
        uint256 start;
        uint256 end;
        uint256 LETAmount;
        uint256 BETAmount;
        uint256 castTime;
    }

    struct TokenCast {
        uint256 timeCast;
        bool isCast;
        bool isClaim;
    }

    mapping(uint256 => TokenCast) public tokenCast;
    mapping(uint256 => uint256) public levelToNum;
    mapping(uint256 => CastInfo) public castInfo;
    mapping(uint256 => NFTInfo) nftInfo;
    mapping(address => EnumerableSet.UintSet) userNotClaim;
    mapping(address => EnumerableSet.UintSet) userhaveClaim;

    mapping(uint256 => EnumerableSet.UintSet) tokenIDCast;
    mapping(uint256 => EnumerableSet.UintSet) tokenIDLL; 
    mapping(uint256 => uint256) public tokenIDToID;


    constructor(
        address nftPool_,
        address betToken,
        address letToken
    ) {
        _init();
        _initCast();
        nftPool = INFTPool(nftPool_);
        BET = IERC20(betToken);
        LET = IERC20(letToken);
    }

    function setExp(address account) external onlyOperator {
        expAddress = IExp(account);
    }

    function setNftPool(address nftPool_) external onlyOperator {
        nftPool = INFTPool(nftPool_);
    }


    function setRate(uint256 rate1, uint256 rate2) external onlyOperator {
        require(
            rate1 > 0 && rate2 > 0 && rate1 < baseRate && rate2 < baseRate && rate1 > rate2, 
            "rate err"
        );
        r1Rate = rate1;
        r2Rate = rate2;
    }

    function setCastInfo(
        uint256[] memory lAmouts,
        uint256[] memory bAmounts,
        uint256[] memory times
    ) external onlyOperator {
        checkCast(lAmouts, bAmounts, times);
        for(uint256 i = 0; i < lAmouts.length; i++) {
            _setCast(i+1, lAmouts[i], bAmounts[i], times[i]);
        }
    }


    function setIsCanCast(bool isCast) external  onlyOperator {
        isCanCast = isCast;
    }

    function castNFT() external nonReentrant {
        (uint256 tokenID, uint256 id) = checkCanCast(msg.sender);

        if(castInfo[id].LETAmount > 0) {
            LET.safeTransferFrom(msg.sender, address(this), castInfo[id].LETAmount);
        }
        if(castInfo[id].BETAmount > 0) {
            BET.safeTransferFrom(msg.sender, address(this), castInfo[id].BETAmount);
        }

        uint256 newID = nftPool.castNFT();

        ++nftInfo[tokenID].castNum;
        nftInfo[newID].r1TokenID = tokenID;
        nftInfo[newID].r2TokenID = nftInfo[tokenID].r1TokenID;

        tokenCast[newID].isCast = true;
        tokenIDToID[newID] = id;
        tokenCast[newID].timeCast = block.timestamp;

        notClaim.add(newID);
        userNotClaim[msg.sender].add(newID);
        tokenIDCast[tokenID].add(newID);
        tokenIDLL[nftInfo[tokenID].r1TokenID].add(newID);
        
        emit CastNFT(msg.sender, tokenID, newID, castInfo[id].LETAmount, castInfo[id].BETAmount, tokenCast[newID].timeCast);
    }

    function checkClaimNFT(uint256 tokenID) public view returns(bool) {
        uint256 id = tokenIDToID[tokenID];
        require(userNotClaim[msg.sender].contains(tokenID), "no NFT");
        require(
            block.timestamp > tokenCast[tokenID].timeCast.add(castInfo[id].castTime), 
            "not timeCast"
        );

        return true;
    }

    function claimNFT(uint256 tokenID) external nonReentrant {
        checkClaimNFT(tokenID);

        notClaim.remove(tokenID);
        userNotClaim[msg.sender].remove(tokenID);


        haveClaim.add(tokenID);
        userhaveClaim[msg.sender].add(tokenID);

        nftPool.claimNFT(msg.sender, tokenID);

        emit ClaimNFT(msg.sender, tokenID);
    }


    function addAmount(uint256 tokenID, uint256 bAmount) external {
        require(msg.sender == address(nftPool), "not nftPool");
        uint256 r1 = nftInfo[tokenID].r1TokenID;
        uint256 r2 = nftInfo[tokenID].r2TokenID;
        uint256 r1Amount = bAmount.mul(r1Rate).div(baseRate);
        uint256 r2Amount = bAmount.mul(r2Rate).div(baseRate);
        if(r1 != 0) {
            _addR1Amount(tokenID, r1, r1Amount);
        } else {
            nftPool.updateUser(tokenID);
            nftInfo[tokenID].amount = nftInfo[tokenID].amount.add(r1Amount);  
            nftInfo[tokenID].notClaim = nftInfo[tokenID].notClaim.add(r1Amount);
        }

        if(r2 != 0) {
            _addR2Amount(tokenID, r2, r2Amount);
        } else {
            nftPool.updateUser(tokenID);
            nftInfo[tokenID].amount = nftInfo[tokenID].amount.add(r2Amount);  
            nftInfo[tokenID].notClaim = nftInfo[tokenID].notClaim.add(r2Amount);            
        }
    }

    function _addR1Amount(uint256 tokenID, uint256 r1, uint256 amount) internal {
        nftPool.updateUser(r1);
        nftInfo[tokenID].r1Amount = nftInfo[tokenID].r1Amount.add(amount);
        nftInfo[r1].lUserAmount = nftInfo[r1].lUserAmount.add(amount);
        nftInfo[r1].notClaim = nftInfo[r1].notClaim.add(amount);
    }

    function _addR2Amount(uint256 tokenID, uint256 r2, uint256 amount) internal {
        nftPool.updateUser(r2);
        nftInfo[tokenID].r2Amount = nftInfo[tokenID].r2Amount.add(amount);
        nftInfo[r2].llUserAmount = nftInfo[r2].llUserAmount.add(amount);
        nftInfo[r2].notClaim = nftInfo[r2].notClaim.add(amount);     
    }


    function checkCanCast(address user) public view returns(uint256, uint256) {
        require(isCanCast, "can not cast");
        require(userNotClaim[user].length() == 0, "need claim before");
        uint256 tokenID = nftPool.userToTokenID(user);
        require(tokenID != 0, "not bing nft vip");
        uint256 level = getTokenIDLevel(tokenID);
        uint256 lNum = levelToNum[level];
        require(lNum != 0, "level not cast");
        require(nftInfo[tokenID].castNum < lNum, "level cast over");

        return (tokenID, getInID(nftInfo[tokenID].castNum+1));
    }


    function _setCast(uint256 id, uint256 lAmount, uint256 bAmount, uint256 time) internal {
        castInfo[id].LETAmount = lAmount;
        castInfo[id].BETAmount = bAmount;
        castInfo[id].castTime = time;
    }

    function checkCast(
        uint256[] memory lAmouts,
        uint256[] memory bAmounts,
        uint256[] memory times
    ) public view returns(bool) {
        require(
            lAmouts.length == bAmounts.length && 
            lAmouts.length == times.length &&
            lAmouts.length == rID,
            "length err"
        );

        require(getRight(lAmouts, bAmounts, times), "arr err");

        return true;
    }
    
    function getRight(
        uint256[] memory lAmouts,
        uint256[] memory bAmounts,
        uint256[] memory times
    ) internal pure returns(bool) {
        for(uint256 i = 0; i < lAmouts.length - 1; i++) {
            if(lAmouts[i] > lAmouts[i+1]) {
                return false;
            }

            if(bAmounts[i] > bAmounts[i+1]) {
                return false;
            }

            if(times[i] > times[i+1]) {
                return false;
            }
        }

        return true;
    }

    function getInID(uint256 num) public view returns(uint256) {
        for(uint256 i = 1; i <= rID; i++) {
            if(castInfo[i].start <= num && castInfo[i].end >= num) {
                return i;
            }
        }
        return 0;
    }
 
    function _initCast() internal {
        _setCastInfo(++rID, 1, 2, 80e18, 300e18, 10 minutes);
        _setCastInfo(++rID, 3, 4, 100e18, 350e18, 20 minutes);
        _setCastInfo(++rID, 5, 6, 120e18, 400e18, 30 minutes);
        _setCastInfo(++rID, 7, 8, 140e18, 500e18, 40 minutes);
        _setCastInfo(++rID, 9, 10, 160e18, 600e18, 50 minutes);
        _setCastInfo(++rID, 11, 20, 180e18, 700e18, 60 minutes);
        _setCastInfo(++rID, 21, 50, 200e18, 800e18, 90 minutes);
        _setCastInfo(++rID, 51, 100, 250e18, 900e18, 120 minutes);
    }

    function _init() internal {
        levelToNum[6] = 3;
        levelToNum[7] = 5;
        levelToNum[8] = 10;
        levelToNum[9] = 20;
        levelToNum[10] = 50;
        levelToNum[11] = 100;
    }

    function _setCastInfo(
        uint256 id,
        uint256 start,
        uint256 end,
        uint256 LETAmount,
        uint256 BETAmount,
        uint256 castTime 
    ) internal {
        castInfo[id].start = start;
        castInfo[id].end = end;
        castInfo[id].LETAmount = LETAmount;
        castInfo[id].BETAmount = BETAmount;
        castInfo[id].castTime = castTime;
    }
 
    function getNotClaim(uint256 tokenID) external view returns(uint256) {
        return nftInfo[tokenID].notClaim;
    }

    function claimTokenIDRward(uint256 tokenID, uint256 amount) external {
        require(msg.sender == address(nftPool), "not pool");
        nftInfo[tokenID].notClaim -= amount;
        nftInfo[tokenID].haveClaim += amount;
    }

    function getNotClaimNum() external view returns(uint256) {
        return notClaim.length();
    }

    function getNotClaimToken(uint256 index) external view returns(uint256, uint256) {
        uint256 tokenID = notClaim.at(index);
        uint256 id = tokenIDToID[tokenID];
        uint256 time = tokenCast[tokenID].timeCast.add(castInfo[id].castTime);
        if(time > block.timestamp) {
            return (tokenID, time.sub(block.timestamp));
        }
        return (tokenID, 0);
    }

    function getHaveClaim()external view returns(uint256) {
        return haveClaim.length();
    }

    function getHaveClaimTokenID(uint256 index) external view returns(uint256) {
        return haveClaim.at(index);
    }

    function getUserNotClaim(address user) external view returns(uint256) {        
        return userNotClaim[user].length();
    }

    function getUserNotClaimTokenID(address user, uint256 index) external view returns(uint256, uint256) {
        uint256 tokenID = userNotClaim[user].at(index);
        uint256 id = tokenIDToID[tokenID];
        uint256 time = tokenCast[tokenID].timeCast.add(castInfo[id].castTime);
        if(time > block.timestamp) {
            return (tokenID, time.sub(block.timestamp));
        }
        return (tokenID, 0);
    }

    function getUserhaveClaim(address user) external view returns(uint256) {
        return userhaveClaim[user].length();
    }

    function getUserhaveClaimTokenID(address user, uint256 index) external view returns(uint256) {
        return userhaveClaim[user].at(index);
    }

    function getTokenIDLNum(uint256 tokenID)external view returns(uint256) {
        return tokenIDCast[tokenID].length();
    }

    function getLTokenID(uint256 tokenID, uint256 index) external view returns(uint256) {
        return tokenIDCast[tokenID].at(index);
    }

    function getTokenIDLLNum(uint256 tokenID)external view returns(uint256) {
        return tokenIDLL[tokenID].length();
    }

    function getLLTokenID(uint256 tokenID, uint256 index) external view returns(uint256) {
        return tokenIDLL[tokenID].at(index);
    }

    function getNftInfo(uint256 tokenID) external view returns(NFTInfo memory) {
        return nftInfo[tokenID];
    }

    function getTokenIDLevel(uint256 tokenID) public view returns(uint256 level) {
        (level,,) = expAddress.tokenIDExp(tokenID);
    }
}