// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IERC721.sol";
import "../common/Operator.sol";
import "../../interfaces/ILuckyGame.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/IExp.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/IPlayerNFT.sol";
import "../../interfaces/ILetDao.sol";

contract NFTPool is Operator {
    event Deposit(address user, uint256 tokenID);
    event Withdraw(address user, uint256 tokenID);
    event ClaimBET(address user, uint256 tokenID, uint256 userAmount);
    event ClaimNFT(address user, uint256 tokenID, uint256 userAmount);
    event CliamLET(address user, uint256 tokenID, uint256 amount);
    event ChangeTokenID(address user, uint256 oldID,  uint256 newID);
    event BuyAndDeposit(address user, uint256 tokenID, uint256 amount, bool isBind);
    event TransferTo(address token, address account, uint256 amount);

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public lockTime = 7 days;
    uint256 constant muti = 1e18;
    uint256 public sellAmount = 150e6;
    uint256 public maxSellNum = 1000;
    uint256 public sellID;
    uint256 public buyNum = 1;
    bool public isOpen = true;
    EnumerableSet.AddressSet whiteList;
    
    
    IERC721 public erc721;
    IExp public expAddress;
    IERC20 public BET;
    IERC20 public LET;
    IERC20 public USDT;

    address public daoAccount;
    address public playerNft;
    address public bonusAccount;

    struct LUnlock {
        uint256 uAmount;
        uint256 nAmount;
    }

    struct TokenIdInfo {
        uint256 lastTime;
        uint256 lastLeaveTime;
    }

    struct UserInfo {
        uint256 letAmount;
        uint256 amount;
    }

    struct UserMint {
        uint256 letAmount;
        uint256 betAmount;
    }

    mapping(address => UserMint) public userMint;
    mapping(uint256 => LUnlock) public lUnLock;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => TokenIdInfo) public tokenIdInfo;
    mapping(uint256 => address) public tokenIdToUser;
    mapping(address => uint256) public userToTokenID;
    mapping(uint256 => uint256) public depositTime;
    mapping(uint256 => uint256) public sellIDToTokenID;
    mapping(uint256 => uint256) public buyTime;
    mapping(uint256 => uint256) public tokenIDToSellID;
    mapping(address => uint256[]) userBuyTokenID;

    constructor(
        address betToken,
        address letToken,
        address usdt
    ) {
        BET = IERC20(betToken);
        LET = IERC20(letToken);
        USDT = IERC20(usdt);
    }

    modifier onlyPlayer() {
        require(msg.sender == playerNft, "not playerNft");
        _;
    }

    function setERC721(address token) external onlyOperator {
        erc721 = IERC721(token);
    }

    function setExp(address account) external onlyOperator {
        expAddress = IExp(account);
    }

    function setLockTime(uint256 time) external onlyOperator {
        lockTime = time;
    }


    function setSellAmount(uint256 amount) external onlyOperator {
        require(amount > 0, "amount err");
        sellAmount = amount;
    }

    function setMaxSellNum(uint256 num) external onlyOperator {
        require(num >= sellID, "num err");
        maxSellNum = num;
    }

    function setPlayerNFT(address account) external onlyOperator {
        playerNft = account;
    }

    function setDaoAccount(address account) external onlyOperator {
        daoAccount = account;
    }

    function setBonusAccount(address account) external onlyOperator {
        bonusAccount = account;
    }

    function setBuyNum(uint256 num) external onlyOperator {
        buyNum = num;
    }


    function mintTo(address account, uint256 num) external onlyOperator {
        require(sellID+num <= maxSellNum, "out range");
        require(account != address(0), "not zero");
        for(uint256 i = 0; i < num; i++) {
            uint256 tokenID = erc721.mintTo(account);  
            sellIDToTokenID[++sellID] = tokenID;
            tokenIDToSellID[tokenID] = sellID;
            buyTime[tokenID] = block.timestamp;
            userBuyTokenID[account].push(tokenID);
        }      
    }

    function buyAndDeposit(bool isBind) external {
        checkBuy(msg.sender, isBind);

        USDT.safeTransferFrom(msg.sender, address(this), sellAmount);
        uint256 tokenID = erc721.mintTo(msg.sender);
        sellIDToTokenID[++sellID] = tokenID;
        tokenIDToSellID[tokenID] = sellID;
        buyTime[tokenID] = block.timestamp;
        userBuyTokenID[msg.sender].push(tokenID);

        if(isBind) {
            _deposit(msg.sender, tokenID);
            emit BuyAndDeposit(msg.sender, tokenID, sellAmount, true);
        } else {
            emit BuyAndDeposit(msg.sender, tokenID, sellAmount, false);   
        }
    }

    function checkBuy(address user, bool isBind) public view returns(bool) {
        if(isOpen) {
            require(whiteList.contains(user), "not white");
            require(userBuyTokenID[user].length < buyNum, "has buy all");
        } 
        if(isBind) {
            require(userToTokenID[user] == 0, "you have bing vip");
        }

        require(sellID+1 <= maxSellNum, "sell out");

        return true;
    }

    function updatePool(uint256 tokenID) public {
        updateWeek();
        address user = tokenIdToUser[tokenID];
        (uint256 unLock, uint256 unTAmount) = getUnLock(tokenID);
        tokenIdInfo[tokenID].lastTime = block.timestamp;
        if(unLock > 0) {
            if(unLock > userInfo[user].amount) {
                unLock = userInfo[user].amount;
            }
            userInfo[user].amount -= unLock;
            lUnLock[tokenID].uAmount = 0;

            BET.mint(tokenIdToUser[tokenID], unLock);
            emit ClaimBET(tokenIdToUser[tokenID], tokenID, unLock);
        }

        if(unTAmount > 0) {
            uint256 nAmount = IPlayerNFT(playerNft).getNotClaim(tokenID);
            if(unTAmount > nAmount) {
                unTAmount = nAmount;
            }
            IPlayerNFT(playerNft).claimTokenIDRward(tokenID, unTAmount);
            lUnLock[tokenID].nAmount = 0;
            BET.mint(tokenIdToUser[tokenID], unTAmount);
            emit ClaimNFT(tokenIdToUser[tokenID], tokenID, unTAmount);
        }
    }

    function deposit(uint256 tokenID) external {
        checkDeposit(msg.sender, tokenID);

        _deposit(msg.sender, tokenID);
    }

    function withdraw(uint256 tokenID) external {
        require(tokenIdToUser[tokenID] == msg.sender, "not owner");
        require(block.timestamp > depositTime[tokenID].add(lockTime), "not unLock time");
        updatePool(tokenID);
        _claimLET(tokenID);
        updateLeaveTime(tokenID);

        tokenIdToUser[tokenID] = address(0);
        userToTokenID[msg.sender] = 0;
        depositTime[tokenID] = 0;

        erc721.transferFrom(address(this), msg.sender, tokenID);
        emit Withdraw(msg.sender, tokenID);
    }

    function claim(uint256 tokenID) external {
        require(tokenIdToUser[tokenID] == msg.sender, "not yours");
        updatePool(tokenID);
        _claimLET(tokenID);
    }



    function changeTokenID(uint256 tokenID) external {
        checkChange(tokenID);

        uint256 oldID = userToTokenID[msg.sender];
        updatePool(oldID);
        updateLeaveTime(oldID);
        updatePool(tokenID);
        userToTokenID[msg.sender] = tokenID;
        tokenIdToUser[tokenID] = msg.sender;

        depositTime[oldID] = 0;
        depositTime[tokenID] = block.timestamp;

        _claimLET(oldID);
        erc721.transferFrom(msg.sender, address(this), tokenID);
        erc721.transferFrom(address(this), msg.sender, oldID);

        emit ChangeTokenID(msg.sender, oldID, tokenID);
    }

    function _deposit(address user, uint256 tokenID) internal {
        updatePool(tokenID);
        userToTokenID[user] = tokenID;
        tokenIdToUser[tokenID] = user;
        depositTime[tokenID] = block.timestamp;

        erc721.transferFrom(user, address(this), tokenID);
        emit Deposit(user, tokenID);
    }

    function _claimLET(uint256 tokenID) internal {
        uint256 amount = userInfo[tokenIdToUser[tokenID]].letAmount;
        if(amount > 0) {
            userInfo[tokenIdToUser[tokenID]].letAmount = 0;
            LET.mint(tokenIdToUser[tokenID], amount);
            emit CliamLET(tokenIdToUser[tokenID], tokenID, amount);
        }
    }


    function updateLeaveTime(uint256 tokenID) internal {
        tokenIdInfo[tokenID].lastLeaveTime = block.timestamp;
    }

    function increaseMint(
        address user, 
        uint256 bAmount, 
        uint256 lAmount
    ) 
        external 
        onlyContractAuth() 
    {
        userInfo[user].letAmount = userInfo[user].letAmount.add(lAmount);
        userInfo[user].amount = userInfo[user].amount.add(bAmount);
        userMint[user].letAmount = userMint[user].letAmount.add(lAmount);
        userMint[user].betAmount = userMint[user].betAmount.add(bAmount);

        if(userToTokenID[user] != 0) {
            IPlayerNFT(playerNft).addAmount(userToTokenID[user], bAmount);
        }
    }

    function checkChange(uint256 tokenID) public view returns(bool) {
        require(erc721.getOwner(tokenID)== msg.sender, "not owner");
        require(userToTokenID[msg.sender] != 0, "not deposit before");
        require(block.timestamp > depositTime[tokenID].add(lockTime), "not unLock time");

        return true;
    }


    function gainExperience(
        address user, 
        uint256 amount,
        uint8 round
    ) 
        external 
        onlyContractAuth()  
    {
        if(userToTokenID[user] != 0) {
            uint256 tokenID = userToTokenID[user];
            expAddress.gainExperience(amount, tokenID, round);
        }   
    }

    function getUnLock(uint256 tokenID) public view returns(uint256, uint256) {
        if(
            tokenIdInfo[tokenID].lastTime == 0 || 
            tokenIdInfo[tokenID].lastTime == block.timestamp ||
            tokenIdInfo[tokenID].lastTime <= tokenIdInfo[tokenID].lastLeaveTime
        ) {
            return (lUnLock[tokenID].uAmount, lUnLock[tokenID].nAmount);
        }

        uint256 lid = getLid(tokenID);
        (uint256 perUn, uint256 wareTime) 
            = expAddress.mintInfo(lid);
        
        uint256 before = lUnLock[tokenID].nAmount.add(lUnLock[tokenID].uAmount).div(perUn);
        if(before >= wareTime) {
            return (lUnLock[tokenID].uAmount, lUnLock[tokenID].nAmount);
        }
        wareTime -= before;
        uint256 time = block.timestamp.sub(tokenIdInfo[tokenID].lastTime);
        if(time > wareTime) {
            time = wareTime;
        }
        (uint256 uAmount, uint256 aTime) = getUserUnLock(tokenID, time, perUn);

        uint256 aAmount;
        if(aTime > 0) {
            aAmount = getTokenIdUnLock(tokenID, aTime, perUn);
        }
        return (uAmount.add(lUnLock[tokenID].uAmount), aAmount.add(lUnLock[tokenID].nAmount));
    }

    function getTokenIdUnLock(
        uint256 tokenID,
        uint256 aTime,
        uint256 perUn
    ) internal view returns(uint256) { 
        uint256 bAmount = IPlayerNFT(playerNft).getNotClaim(tokenID);
        uint256 aAmount = perUn.mul(aTime);

        if(bAmount > aAmount) {
            return aAmount;
        } else {
            return bAmount;
        }
    }

    function getUserUnLock(
        uint256 tokenID,
        uint256 time,
        uint256 perUn
    ) internal view returns(uint256, uint256) {
        uint256 amountUn = time.mul(perUn);
        if(userInfo[tokenIdToUser[tokenID]].amount <= amountUn) {
            uint256 tTime = userInfo[tokenIdToUser[tokenID]].amount.div(perUn);
            return (userInfo[tokenIdToUser[tokenID]].amount, time.sub(tTime));
        } else {
            return (amountUn, 0);
        }
    }

    function getLid(uint256 tokenID) public view returns(uint256 lid) {
        (lid,,) = expAddress.tokenIDExp(tokenID);
    }

    function checkDeposit(address user, uint256 tokenID) public view returns(bool) {
        require(erc721.getOwner(tokenID) == user, "not owner");
        require(userToTokenID[user] == 0, "you are vip");

        return true;
    }

    function getUnLockTime(uint256 tokenID) external view returns(uint256) {
        require(tokenIdToUser[tokenID] != address(0), "not deposit");
        if(
            block.timestamp >= depositTime[tokenID] && 
            block.timestamp <= depositTime[tokenID].add(lockTime)
        ) {
            return depositTime[tokenID].add(lockTime).sub(block.timestamp);
        }
        return 0;

    }

    function castNFT() external onlyPlayer returns(uint256) {
        updateWeek();
        return erc721.mintTo(address(this));
    }

    function claimNFT(address user, uint256 tokenID) external onlyPlayer {
        updateWeek();
        erc721.transferFrom(address(this), user, tokenID);
    }

    function updateWeek() public {
        if(address(0) != daoAccount) {
            ILetDao(daoAccount).updateWeek();
        }
    }

    function mintLET(uint256 amount) external {
        require(msg.sender == bonusAccount, "not bonusAccount");
        LET.mint(msg.sender, amount);
    }


	function transferTo(address token, address account, uint256 amount) public onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "not enough");
        IERC20(token).safeTransfer(account, amount);
        
        emit TransferTo(token, account, amount);
    } 


    function  setIsOpen(bool isOpen_) external onlyOperator {
        isOpen = isOpen_;
    }

    function addOrRemoveWhiteList(address[] memory accounts, bool isAdd) external onlyOperator {
        if(isAdd) {
            for(uint256 i = 0; i < accounts.length; i++) {   
                whiteList.add(accounts[i]);
            }
        } else {
            for(uint256 i = 0; i < accounts.length; i++) {  
                whiteList.remove(accounts[i]); 
            }
        }

    } 

    function getWhiteListNum() external view returns(uint256) {
        return whiteList.length();
    }

    function getWhiteListAddress(uint256 index) external view returns(address) {
        return whiteList.at(index);
    }

    function getIdIsInWhiteList(address user) external view returns(bool) {
        return whiteList.contains(user);
    }

    function getBuyNum(address user) external view returns(uint256) {
        return userBuyTokenID[user].length;
    }

    function getUserBuyTokenID(address user) external view returns(uint256[] memory) {
        return userBuyTokenID[user];
    }

    function getBuyTokenID(address user, uint256 index) external view returns(uint256) {
        return userBuyTokenID[user][index];
    }

    function updateUser(uint256 tokenID) external onlyPlayer {
        address user = tokenIdToUser[tokenID];
        if(user != address(0)) {
            (lUnLock[tokenID].uAmount, lUnLock[tokenID].nAmount) = getUnLock(tokenID);
            if(lUnLock[tokenID].uAmount > userInfo[user].amount) {
                lUnLock[tokenID].uAmount = userInfo[user].amount;
            }
            uint256 nAmount = IPlayerNFT(playerNft).getNotClaim(tokenID);
            if(lUnLock[tokenID].nAmount > nAmount) {
                lUnLock[tokenID].nAmount = nAmount;
            }
            tokenIdInfo[tokenID].lastTime = block.timestamp;
        }
    }
}