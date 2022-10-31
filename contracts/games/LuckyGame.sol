// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../common/Op.sol";
import "../../interfaces/ILuckyPool.sol";
import "../../libraries/Address.sol";
import "../../libraries/EnumerableSet.sol";
import "../../types/ReentrancyGuard.sol";
import "../../interfaces/INFTPool.sol";

contract LuckyGame is Op, ReentrancyGuard {
    event Bet(
        address user, 
        uint256 amount, 
        uint256 oddID, 
        uint256 betID, 
        uint256 oddNum, 
        uint256 betNum,
        uint256 round
    );
    event SetBlockHash(uint256 blm, uint256 winNum, bytes32 hash);
    event Claim(uint256 userBetOddNum, uint256 amount);

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant zeroHash =  0x0000000000000000000000000000000000000000000000000000000000000000;
    address public trigAccount;
    uint256 public bNumber1 = 3;
    uint256 public bNumber2 = 1;
    uint256 public coef1 = 930;
    uint256 public coef2 = 20;
    uint256 public deci = 9000;
    uint256 public trigTime = 5 minutes;
    uint256 public oddNum;
    uint256 public totalBetNum;
    uint256 constant baseNum = 16;
    uint256 public minBetAmount = 1e6;
    uint256 public maxBetAmount = 50e6; 
    uint256 dealID;

    EnumerableSet.UintSet noBlockHash;
    EnumerableSet.UintSet haveBlockHash;
    ILuckyPool public luckyPool;
    INFTPool public nftPool;
    IERC20 USDT;

    mapping(uint256 => EnumerableSet.UintSet) waitHash;
    mapping(address => UserBet) public userBet;
    mapping(address => mapping(uint256 => uint256)) public userOddToTotal;
    mapping(address => mapping(uint256 => uint256)) public userBetNumToTotal;
    mapping(uint256 => UserInfo) oddInfo;
    mapping(uint256 => UserInfo) betNumInfo;
    mapping(uint256 => mapping(uint256 => uint256)) public oddRoundToBetNum;
    mapping(uint256 => uint256) public totalBetToOdd;

    uint256 public codeID;
    mapping(bytes32 => bool) public isCodeExist;
    mapping(bytes32 => uint256) public codeToID;
    mapping(uint256 => bytes32) public idToCode;
    mapping(uint256 => uint256[]) idToOption;
    mapping(uint256 => mapping(uint8 => uint256)) public oddRoudPaid;
    mapping(uint256 => WinInfo) public winInfo;
    mapping(uint8 => uint256) public radio;
    mapping (uint256 => uint256) public blockStartBetTime;
    mapping(uint256 => mapping(address => uint256)) public userTotalBet;

    struct UserBet {
        uint256 betOddNum;
        uint256 betNum;
    }

    struct UserInfo {
        address user;
        uint256[] option;
        uint256 amount;
        uint256 blockNumber;
        uint256 letAmount;
        uint256 betAmount;
        uint8 round;
        uint8 typeGame;
        uint8 size;
        bool isClaim;
    }


    struct WinInfo {
        bytes32 blockHash;
        uint256 winNumber;
        uint8 sizeBS;
        uint8 sizeSD;
    }
    
    struct QUser {
        bytes32 hash;
        uint256 oNum;
        uint256 winNum;
        uint256 paid;
        uint256 bAmount;
        uint256 lAmount;
        uint256 blockNum;
        uint256 rateF;
        uint256 amount;
        uint8 round;
        uint8 typeGame;
        uint8 size;
        bool isWin;
        bool isClaim;
    }

    struct NewInfo {
        address user;
        bytes32 hash;
        uint256[] option;
        uint256 paid;
        uint256 amount;
        uint256 bAmount;
        uint256 lAmount;
        uint256 rateF;
        uint8 typeGame;
        uint8 size;
        bool isWin;
    }


    constructor (
        address luckyPool_
    )  {
        luckyPool = ILuckyPool(luckyPool_);
        USDT = IERC20(luckyPool.USDT());
        _setRadio();
    }

    function setBetAmount(uint256 min, uint256 max) external  onlyOperator {
        require(max > min && min > 0, "range err");
        minBetAmount = min;
        maxBetAmount = max;
    }

    function setNFTPool(address account) external onlyOperator {
        nftPool = INFTPool(account);
    }

    function setBETNum(uint256 num1, uint256 num2) external onlyOperator {
        require(num1 > 0 && num2 > 0, "num err");
        bNumber1 = num1;
        bNumber2 = num2;
    } 

    function setLETNum(uint256 num1, uint256 num2, uint256 num3) external onlyOperator {
        require(num1 > 0 && num2 > 0 && num3 > 0 && num3 < baseRate, "num err");
        coef1 = num1;
        coef2 = num2;
        deci = num3;
    } 

    function setTrigTime(uint256 time) external onlyOperator {
        trigTime = time;
    }

    function setTrigAccount(address addr) external onlyOperator {
        trigAccount = addr;
    }

    function setBlockHash(uint256 blm, bytes32 hash) external {
        hash = checkSet(msg.sender, blm, hash);
        uint256 winNum = getHashLastNum(hash);
        _setBlockHash(blm, hash, winNum);
        updateBet();
    }

    function bethSetBlockHash(uint256[] memory blms, bytes32[] memory hashs) external {
        require(blms.length == hashs.length, "length err");
        for(uint256 i = 0; i < blms.length; i++) {
            uint256 blm = blms[i];
            bytes32 hash = hashs[i];
            hash = checkSet(msg.sender, blm, hash);
            uint256 winNum = getHashLastNum(hash);
            _setBlockHash(blm, hash, winNum);
        }
        updateBet();
    }

    function setRadio(uint8[] memory round, uint256[] memory radios) external onlyOperator {
        uint256 len = round.length;
        uint256 len1 = radios.length;
        require(len <= 5 && len > 0 && len == len1, "length err");
        for(uint8 i = 0; i < len; i++) {
            require(radios[i] > 0 && radios[i] <= baseRate, "radio err");
            radio[round[i]] = radios[i];
        }
    }

    function _setRadio() internal {
        radio[1] = 7500;
        radio[2] = 9000;
        radio[3] = 9300;
        radio[4] = 9650;
        radio[5] = 9900;
    }


    function bet(uint256 amount, uint8 tGame, uint256[] memory option) external {
        (bool isWin, bytes32 hash, uint256 winNum, uint256 pAmount) = checkBefore(msg.sender);
        _claim(hash, winNum, isWin);
        (uint256 paid, uint8 size) = checkBet(msg.sender, amount, tGame, option, pAmount);
        updateBet();

        ++oddNum;
        userOddToTotal[msg.sender][++userBet[msg.sender].betOddNum] = oddNum;
        oddRoudPaid[oddNum][1] = paid;

        _bet(tGame, size, oddNum, amount, option);

        USDT.safeTransferFrom(msg.sender, address(luckyPool), amount);
        luckyPool.addBetAmount(msg.sender, amount);
    }


    function claim() public nonReentrant {
        (bytes32 hash, uint256 winNum) = checkClaim(msg.sender, userBet[msg.sender].betOddNum);
        _claim(hash, winNum, true);
        updateBet();
    }

    function _claim(bytes32 hash, uint256 winNum, bool isWin) internal {
        luckyPool.updateWeek();

        uint256 oddID = userOddToTotal[msg.sender][userBet[msg.sender].betOddNum];

        oddInfo[oddID].isClaim = true;

        uint256 blm = oddInfo[oddID].blockNumber;
        if(winInfo[blm].blockHash == zeroHash) {
            _setBlockHash(blm, hash, winNum);
        }
        
        if(isWin) {
            uint256 paid = oddRoudPaid[oddID][oddInfo[oddID].round];
            luckyPool.userClaim(msg.sender, paid);
            emit Claim(userBet[msg.sender].betOddNum, paid);
        }
    }

    function betNextRound(uint8 tGame, uint256[] memory option) external nonReentrant {
        (bytes32 hash, uint256 winNum) = _checkRound(msg.sender, userBet[msg.sender].betOddNum);
        updateBet();
        luckyPool.updateWeek();
        uint256 oddID = userOddToTotal[msg.sender][userBet[msg.sender].betOddNum];
        uint256 blm = oddInfo[oddID].blockNumber;
        if(winInfo[blm].blockHash == zeroHash) {
            _setBlockHash(blm, hash, winNum);
        }

        uint256 lastPaid = oddRoudPaid[oddID][oddInfo[oddID].round];
        uint256 paid = getRoundPaid(oddInfo[oddID].round+1, uint8(option.length), lastPaid);
        require(luckyPool.getTotalAmount() >= lastPaid.add(paid), "pool not enough");
    
        uint8 size = _checkBet(oddInfo[oddID].round+1, tGame, lastPaid, option);
        oddRoudPaid[oddID][oddInfo[oddID].round+1] = paid;

        _bet(tGame, size, oddID, lastPaid, option);
    }

    function checkRound(
        address user, 
        uint256 userBetOddNum, 
        uint8 tGame, 
        uint256[] memory option
    ) public view returns(bytes32 hash, uint256 num) {
        uint256 oddID = userOddToTotal[user][userBetOddNum];
        require(
            userBet[user].betOddNum > 0 && 
            userBet[user].betOddNum <= userBetOddNum &&
            oddInfo[oddID].round > 0 && oddInfo[oddID].round < 5,
            "next err"
        );

        (hash, num) = checkClaim(user, userBetOddNum);
        
        uint256 lastPaid = oddRoudPaid[oddID][oddInfo[oddID].round];
        uint256 paid = getRoundPaid(oddInfo[oddID].round+1, uint8(option.length), lastPaid);
        require(luckyPool.getTotalAmount() >= lastPaid.add(paid), "pool not enough");
        _checkBet(oddInfo[oddID].round+1, tGame, lastPaid, option);
    }



    function setNumber(uint256 blm,  uint256 winNum) internal {
        if(winNum < 8) {
            winInfo[blm].sizeBS = 1;
        } else {    
            winInfo[blm].sizeBS = 2;
        }

        if(winNum.mod(2) == 1) {
            winInfo[blm].sizeSD == 1;
        } else {
            winInfo[blm].sizeSD == 2;
        }
    }


     function updateBet() public {
        if(noBlockHash.length() > 0) {
            ++dealID;
        }

        for(uint256 i = 0; i < noBlockHash.length(); i++) {
            uint256 blm = noBlockHash.at(i);
            bytes32 hash = blockhash(blm);
            if(hash != zeroHash) {
                uint256 winNum = getHashLastNum(hash);
                winInfo[blm].blockHash = hash;
                winInfo[blm].winNumber = winNum;
                setNumber(blm, winNum);

                haveBlockHash.add(blm);
                waitHash[dealID].add(blm);
                emit SetBlockHash(blm, winInfo[blm].winNumber, hash);
            }
        }

        for(uint256 i = 0; i < waitHash[dealID].length(); i++) {
            noBlockHash.remove(waitHash[dealID].at(i));
        }
    }

    function _bet(
        uint8 tGame, 
        uint8 size, 
        uint256 oNum, 
        uint256 amount, 
        uint256[] memory option
    ) internal {
        ++totalBetNum;
        totalBetToOdd[totalBetNum] = oNum;
        userBetNumToTotal[msg.sender][++userBet[msg.sender].betNum] = totalBetNum;
        userTotalBet[luckyPool.nob()][msg.sender] = userTotalBet[luckyPool.nob()][msg.sender].add(amount);

        uint256 blm = block.number;
        noBlockHash.add(blm);
        require(noBlockHash.contains(blm), "add err");
        
        if(blockStartBetTime[blm] == 0) {
            blockStartBetTime[blm] = block.timestamp;
        }

        (uint256 bAmount, uint256 lAmount) = getTokenAmount(amount, ++oddInfo[oNum].round);

        oddInfo[oNum] = UserInfo(
            msg.sender,
            option,
            amount,
            blm,
            lAmount,
            bAmount,
            oddInfo[oNum].round,
            tGame,
            size,
            false
        );

        oddRoundToBetNum[oNum][oddInfo[oNum].round] = totalBetNum;
        betNumInfo[totalBetNum] = oddInfo[oNum];

        bytes32 code = getOptionCode(option);
        if(!isCodeExist[code]) {
            isCodeExist[code] = true;
            codeToID[code] = ++codeID;
            idToCode[codeID] = code;
            idToOption[codeID] = option;
        }

        luckyPool.addMint(msg.sender, amount, bAmount, lAmount);
        nftPool.increaseMint(msg.sender, bAmount, lAmount);
        nftPool.gainExperience(msg.sender, amount, oddInfo[oNum].round);

        emit Bet(msg.sender, amount, oNum, totalBetNum, userBet[msg.sender].betOddNum, userBet[msg.sender].betNum, oddInfo[oddNum].round);
    }

    function checkSet(address account, uint256 blm, bytes32 hash) public view returns(bytes32) {
        require(
            (account == owner() || account == trigAccount) &&
            blm < block.number &&
            block.timestamp > blockStartBetTime[blm].add(trigTime) &&
            noBlockHash.contains(blm) &&
            hash != zeroHash,
            "can not set"
        );
  
        bytes32 hash1 = blockhash(blm);   
        if(hash1 != zeroHash && hash1 != hash) {
            return hash1;
        }

        return hash;
    }

    function _setBlockHash(uint256 blm, bytes32 hash, uint256 winNum) internal {
        winInfo[blm].blockHash = hash;
        winInfo[blm].winNumber = winNum;
        setNumber(blm, winNum);

        noBlockHash.remove(blm);
        haveBlockHash.add(blm);

        emit SetBlockHash(blm, winInfo[blm].winNumber, hash);
    }

    function getHash(uint256 oddID) public view returns(bytes32 hash) {
        return _gethash(oddInfo[oddID].blockNumber);
    }

    function getBetBHash(uint256 betNum) public view returns(bytes32 hash) {
        return _gethash(betNumInfo[betNum].blockNumber);
    }

    function _gethash(uint256 blm) internal view returns(bytes32 hash) {
        if(winInfo[blm].blockHash != zeroHash) {
            hash = winInfo[blm].blockHash;
        } else {
            hash = blockhash(blm);
            require(hash != zeroHash, "too long");
        }
    }

    function checkClaim(address user, uint256 userBetOddNum) public view returns(bytes32, uint256) {
        uint256 oddID = userOddToTotal[msg.sender][userBet[msg.sender].betOddNum];
        return _checkClaim(user, oddInfo[oddID].typeGame, oddInfo[oddID].size, userBetOddNum);
    }

    function _checkClaim(address user, uint8 tGame, uint8 size, uint256 userBetOddNum) internal view returns(bytes32, uint256) {
        uint256 oddID = userOddToTotal[user][userBetOddNum];
        bytes32 hash = _gethash(oddInfo[oddID].blockNumber);
        require(
            user == oddInfo[oddID].user &&
            !oddInfo[oddID].isClaim &&
            oddID > 0 &&
            oddInfo[oddID].blockNumber < block.number &&
            isCanBet(oddRoudPaid[oddID][oddInfo[oddID].round], 0), 
            "claim err"
        );
   
        uint256 winNum = getHashLastNum(hash);
        if(tGame == 1) {
            if(winNum < 8) {
                require(size == 1, "select big");
            } else {
                require(size == 2, "select small");
            }
        }

        if(tGame == 2) {
            if(winNum.mod(2) == 1) {
                require(size == 1, "select double");
            } else {
                require(size == 2, "select single");
            }
        }

        if(oddInfo[oddID].typeGame == 3) {
            require(isInArray(winNum, oddID), "guess err");
        }
        
        return (hash, winNum);
    } 

    function isInArray(uint256 winNum, uint256 oddID) public view returns(bool) {
        for(uint256 i = 0; i < oddInfo[oddID].option.length; i++) {
            if(winNum == oddInfo[oddID].option[i]) {
                return true;
            }
        }
        return false;
    }

    function isBInArray(uint256 winNum, uint256 betNum) public view returns(bool) {
        for(uint256 i = 0; i < betNumInfo[betNum].option.length; i++) {
            if(winNum == betNumInfo[betNum].option[i]) {
                return true;
            }
        }
        return false;
    }

    
    function getHashLastNum(bytes32 hash) public pure returns(uint256) {
        return uint256(hash).mod(16);
    }


    function _checkRound(address user, uint256 userBetOddNum) internal view returns(bytes32, uint256) {
        uint256 oddID = userOddToTotal[user][userBetOddNum];
        require(
            userBet[user].betOddNum > 0 && 
            userBet[user].betOddNum <= userBetOddNum &&
            oddInfo[oddID].round > 0 && oddInfo[oddID].round < 5,
            "not bet"
        );
        return checkClaim(user, userBetOddNum);
    }

    function getRoundPaid(uint8 round, uint256 len, uint256 amount) public view returns(uint256) {
        if(round == 0 || round > 5 || len == 0 || len > 10) {
            return 0;
        }
        uint256 rate = radio[round];

        return amount.mul(baseNum).mul(rate).div(len).div(baseRate);
    }


    function getOptionCode(uint256[] memory option) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(option));
    }


    function getIDToOption(uint256 id) public view returns(uint256[] memory) {
        return idToOption[id];
    }

    function getCodeToOption(bytes32 code) public view returns(uint256[] memory) {
        return idToOption[codeToID[code]];
    }

    function getBetNumInfo(uint256 betNum_) external view returns(UserInfo memory) {
        return betNumInfo[betNum_];
    }

    function getOddInfo(uint256 oddNum_) external view returns(UserInfo memory) {
        return oddInfo[oddNum_];
    }

    function getTokenAmount(uint256 amount, uint8 round) public view returns(uint256, uint256) {
        amount = amount.mul(1e18).div(1e6);
        if(round > 5 || round == 0) {
            return (0, 0);
        }
        uint256 num = luckyPool.nob().div(bNumber1).add(bNumber2);
        if(num > 10) {
            num = 10;
        }

        uint256 value = amount.mul(uint256(round)).div(num);
        if(round > 0 && round <= 3) {
            return (value, 0);
        }

        return (value, getLAmount(amount, round));
    }   

    function getLAmount(uint256 amount, uint8 round) internal view returns(uint256) {
        uint256 _deci = deci;
        uint256 _base = baseRate;
        uint256 _num = luckyPool.nob().div(coef2);
        if(_num == 0) {
            _deci = 1;
            _base = 1;
        }
        if(_num > 1) {
            for(uint256 i = 0; i < _num.sub(1); i++) {
                _deci = _deci.mul(_deci);
                _base = _base.mul(_base);
            }
        }

        return amount.mul(uint256(round)).mul(_deci).div(coef1).div(_base);
    }


    function checkOption(uint256[] memory option) public pure returns(bool) {
        if(option.length == 1) {
            if(option[0] > 15) {
                return false;
            }
        }
        for(uint256 i = 0; i < option.length - 1; i++) {  
            if(option[i] >= option[i + 1] || option[i] > 15 || option[i + 1] > 15) {
                return false;
            }
        }
        return true;
    }


    function _checkBet(
        uint8 round,
        uint8 tGame,
        uint256 amount, 
        uint256[] memory option
    ) internal pure returns(uint8 size) {
        uint256 num = option.length;
        require(
            amount > 0 && round <= 5 && tGame > 0 && tGame < 4 && num <= 10 && num > 0, 
            "param err"
        );
        size = _getSize(tGame, option);
    }

    function _getSize(uint8 tGame, uint256[] memory option) internal pure returns(uint8 size) {
        if(tGame == 1) {
            size = checkSize(option);
            require(size != 0, "bs err");
        } else if(tGame == 2) {
            size = checkSingle(option);
            require(size != 0, "sd err");
        } else {
            require(checkOption(option), "option err");
            size = 0;
        }
    }


    function checkSingle(uint256[] memory option) public pure returns(uint8) {
        if(option.length != 8) {
            return 0;
        }

        if(option[0] == 1) {
            for(uint256 i = 0; i < 7; i++) {
                if(option[i] > option[i+1] || option[i+1].mod(2) != 1 || option[i+1] > 15) {
                    return 0;
                }
            }
            return 1;
        }


        if(option[0] == 0) {
            for(uint256 i = 0; i < 7; i++) {
                if(option[i] > option[i+1] || option[i+1].mod(2) != 0 || option[i+1] > 15) {
                    return 0;
                }
            }
            return 2;
        }

        return 0;
    }

    function checkSize(uint256[] memory option) public pure returns(uint8) {
        if(option.length != 8) {
            return 0;
        }

        if(option[0] == 0) {
            for(uint256 i = 0; i < 7; i++) {
                if(option[i] > option[i+1] || option[i+1] > 7) {
                    return 0;
                }
            }
            return 1;
        }

        if(option[0] == 8) {
            for(uint256 i = 0; i < 7; i++) {
                if(option[i] > option[i+1] || option[i+1] > 15) {
                    return 0;
                }
            }
            return 2;
        }
        return 0;
    }

    function isCanBet(uint256 paid, uint256 amount) public view returns(bool) {
        return luckyPool.getTotalAmount().add(amount) >= paid;
    }

    function checkBet(        
        address user, 
        uint256 amount, 
        uint8 tGame,
        uint256[] memory option,
        uint256 pAmount
    ) public view returns(uint256, uint8) {
        (uint256 sTime,) = luckyPool.bnbTime(1);
        uint8 size = _checkBet(1, tGame, amount, option); 
        uint256 paid = getRoundPaid(1, uint8(option.length), amount);
        require(luckyPool.getTotalAmount().add(amount) >= paid.add(pAmount), "pool not enough");
        require(
            luckyPool.initTime() && sTime < block.timestamp &&
            USDT.balanceOf(user) >= amount &&
            amount >= minBetAmount && amount <= maxBetAmount, 
            "not deposit"
        );
      
        return (paid, size);
    }
    
    function checkBefore(address user) 
        public 
        view 
        returns(bool isWin, bytes32 hash, uint256 winNum, uint256 paid) 
    {
        uint256 oddID = userOddToTotal[user][userBet[user].betOddNum];
        if(oddID > 0 && !oddInfo[oddID].isClaim) {
            require(oddInfo[oddID].blockNumber < block.number, "bNum err");
            hash = _gethash(oddInfo[oddID].blockNumber);     
            winNum = getHashLastNum(hash); 
            if(isInArray(winNum, oddID)) {
                require(isCanBet(oddRoudPaid[oddID][oddInfo[oddID].round], 0), "not enough");
                isWin = true;
                paid = oddRoudPaid[oddID][oddInfo[oddID].round];
            } else {
                isWin = false;
            }
        }
    }
    
    function getUserInfo(address user) external view returns(QUser memory quser, uint256[] memory option) {
        uint256 oNum = userOddToTotal[user][userBet[user].betOddNum];
        quser.oNum = oNum;
        quser.round = oddInfo[oNum].round;
        quser.hash = getHash(oNum);
        quser.winNum = getHashLastNum(quser.hash);
        quser.paid = getRoundPaid(quser.round, oddInfo[oNum].option.length, oddInfo[oNum].amount);
        quser.isWin = isInArray(quser.winNum, oNum);
        quser.isClaim = oddInfo[oNum].isClaim;
        quser.typeGame = oddInfo[oNum].typeGame;
        quser.size = oddInfo[oNum].size;
        if(!quser.isWin) {
            quser.paid = 0;
        }
        
        quser.lAmount = oddInfo[oNum].letAmount;
        quser.bAmount = oddInfo[oNum].betAmount;
        quser.amount = oddInfo[oNum].amount;
        option = oddInfo[oNum].option;
    }

    function getNoHashBlockNum() external view returns(uint256) {
        return noBlockHash.length();
    }

    function getNoHashBlock(uint256 index) external view returns(uint256, uint256) {
        uint256 blm = noBlockHash.at(index);
        return (blm, blockStartBetTime[blm]);
    }

    function getNoBlockContains(uint256 blm) external view returns(bool) {
        return noBlockHash.contains(blm);
    }

    function getHashBlockNum() external view returns(uint256) {
        return haveBlockHash.length();
    }

    function getHashBlock(uint256 index) external view returns(uint256) {
        return haveBlockHash.at(index);
    }

    function getBlockContains(uint256 blm) external view returns(bool) {
        return haveBlockHash.contains(blm);
    }

    function getOddNumInfo(uint256 oNum) 
        public 
        view 
        returns(QUser memory quser, uint256[] memory option) 
    {
        quser.oNum = oNum;
        quser.round = oddInfo[oNum].round;
        quser.hash = getHash(oNum);
        quser.winNum = getHashLastNum(quser.hash);
        quser.paid = getRoundPaid(quser.round, oddInfo[oNum].option.length, oddInfo[oNum].amount);
        quser.isWin = isInArray(quser.winNum, oNum);
        quser.isClaim = oddInfo[oNum].isClaim;
        if(!quser.isWin) {
            quser.paid = 0;
        }
        quser.typeGame = oddInfo[oNum].typeGame;
        quser.size = oddInfo[oNum].size;
        quser.lAmount = oddInfo[oNum].letAmount;
        quser.bAmount = oddInfo[oNum].betAmount;
        option = oddInfo[oNum].option;
        quser.blockNum = oddInfo[oNum].blockNumber;
        quser.rateF = baseNum.mul(radio[oddInfo[oNum].round]).div(oddInfo[oNum].option.length);
        quser.amount = oddInfo[oNum].amount;
    }


    function getRoundInfo(uint256 oNum, uint8 round) 
        public 
        view 
        returns(QUser memory quser, uint256[] memory option) 
    {
        uint256 betNum = oddRoundToBetNum[oNum][round];

        quser.oNum = oNum;
        quser.round = round;
        quser.hash = getBetBHash(betNum);

        quser.winNum = getHashLastNum(quser.hash);
        quser.paid = getRoundPaid(quser.round, betNumInfo[betNum].option.length, betNumInfo[betNum].amount);
        quser.isWin = isBInArray(quser.winNum, betNum);
        quser.isClaim = betNumInfo[betNum].isClaim;
        if(!quser.isWin) {
            quser.paid = 0;
        }
        
        quser.typeGame = betNumInfo[betNum].typeGame;
        quser.size = betNumInfo[betNum].size;

        quser.lAmount = betNumInfo[betNum].letAmount;
        quser.bAmount = betNumInfo[betNum].betAmount;
        option = betNumInfo[betNum].option;
        quser.blockNum = betNumInfo[betNum].blockNumber;
        quser.rateF = baseNum.mul(radio[round]).div(betNumInfo[betNum].option.length);
        quser.amount = betNumInfo[betNum].amount;
    }

    function getNewInfo(uint256 betNum) external view returns(NewInfo memory newInfo) {
        newInfo.user = betNumInfo[betNum].user;
        newInfo.hash = getBetBHash(betNum);
        newInfo.amount = betNumInfo[betNum].amount;
        newInfo.option = betNumInfo[betNum].option;
        newInfo.typeGame = betNumInfo[betNum].typeGame;
        newInfo.size = betNumInfo[betNum].size;

        uint256 winNum = getHashLastNum(newInfo.hash);
        newInfo.isWin = isBInArray(winNum, betNum);
        newInfo.paid = getRoundPaid(betNumInfo[betNum].round, betNumInfo[betNum].option.length, betNumInfo[betNum].amount);
        if(!newInfo.isWin) {
            newInfo.paid = 0;
        }
        newInfo.bAmount = betNumInfo[betNum].letAmount;
        newInfo.lAmount = betNumInfo[betNum].betAmount;
        uint8 round = betNumInfo[betNum].round;
        newInfo.rateF = baseNum.mul(radio[round]).div(betNumInfo[betNum].option.length);
    }
}
