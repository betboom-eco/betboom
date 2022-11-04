// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../common/Op.sol";
import "../../libraries/Address.sol";
import "../../libraries/EnumerableSet.sol";
import "../../types/ReentrancyGuard.sol";
import "../../interfaces/INFTPool.sol";
import "../../interfaces/IBallGame.sol";
import "../../interfaces/IRewardPool.sol";
import "../../interfaces/INFTPool.sol";

contract FactoryBallGame is Op, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Claim(address user, uint256 cupID, uint256 totalID, uint256 amount); 
    event CaculateMatch(uint256 cupID, uint256 mID);
    event Bet(
        address user,
        uint256 cupID,
        uint256 mID,
        uint256 betID
    );   
    event AddTeam(uint256 id, string  name, string site);
    event SetTeam(uint256 tID, string name, string site);

    uint256 public totalTeamID;
    uint256 public totalCupID;
    uint256 public feeRate = 200;
    uint256 public lastTime;
    uint256 public notCacuNum;

    address public caculateAccount;
    IRewardPool public rewardPool;
    IERC20 public betToken;
    EnumerableSet.AddressSet enableGame;
    EnumerableSet.AddressSet unEnableGame;
    INFTPool public nftPool;

    struct CupInfo {
        string name;
        address token;
        uint256 upRate;
        uint256 maxTeamNum;
        uint256 startTime;
        uint256 endTime;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 totalBetID;
        bool isPlay;
    }

    struct Team {
        string name;
        string site;
    }

    struct MatchInfo {
        uint256 homeTeam;
        uint256 visitingTeam;
        uint256 startTime;
        uint256 matchTime;
        uint256 homeGoals;
        uint256 visitingGoals;
        uint8 winType;
        bool isOpen;
        bool isCancel;
        bool isCaculate;
        bool hasBet;
    }

    struct BetInfo {
        address user;
        address gameAddress;
        uint256 gType;
        uint256 cupID;
        uint256 mID;
        uint256 amount;
        uint256 value;
        uint256 time;
        uint256 payRate;
        uint256 index;
        uint256 bAmount;
        uint256 lAmount;
        int256 choice;
        bool isSignle;
        bool isClaim;
    }

    struct CupStatus {
        uint256 firstTime;
        bool hasBet;
    }

    mapping(uint256 => CupStatus) public cupStatus;
    mapping(uint256 => Team) public team;
    mapping(uint256 => EnumerableSet.UintSet) teamID;
    mapping(uint256 => CupInfo) public cupInfo;    
    mapping(uint256 => uint256) public matchID;
    mapping(uint256 => mapping(uint256 => MatchInfo)) public matchInfo;
    mapping(uint256 => mapping(uint256 => EnumerableSet.AddressSet)) midGameAddress;
    mapping(uint256 => mapping(uint256 => BetInfo)) betInfo;
    mapping(address => mapping(uint256 => EnumerableSet.UintSet)) userMatchID;
    mapping(address => mapping(uint256 => EnumerableSet.UintSet)) userBetID;
    mapping(address => mapping(uint256 => mapping(uint256 => EnumerableSet.UintSet))) userBetMatchID;
    mapping(address => uint256) public gameType;

    constructor(
        address rPool,
        address nPool
    ) {
        rewardPool = IRewardPool(rPool);
        nftPool = INFTPool(nPool);
        betToken = IERC20(rewardPool.rewardToken());
    }


    modifier isExist(uint256 cupID) {
        require(cupID > 0 && cupID <= totalCupID, "not exist");
        _;
    }

    modifier notStart(uint256 cupID) {
        require(cupInfo[cupID].startTime > block.timestamp, "has start");
        _;
    }

    modifier notEnd(uint256 cupID) {
        require(cupInfo[cupID].endTime > block.timestamp, "has end");
        _;
    }

    function setBetAmount(uint256 cupID, uint256 min, uint256 max) 
        external 
        onlyOperator
        notEnd(cupID)
    {
        require(min > 0 && max > 0 && max > min, "range errr");
        cupInfo[cupID].minAmount = min;
        cupInfo[cupID].maxAmount = max;
    }

    function claim(uint256 cupID, uint256 totalID) external {
        uint256 amount = checkClaim(msg.sender, cupID, totalID);
        betInfo[cupID][totalID].isClaim = true;
        rewardPool.cliam(msg.sender, amount);

        emit Claim(msg.sender, cupID, totalID, amount);
    }

    function claimMatch(uint256 cupID, uint256 mID) external {
        require(matchInfo[cupID][mID].isCaculate, "can not claim");
        uint256 len = userBetMatchID[msg.sender][cupID][mID].length();
        require(len > 0, "no bet");
        uint256 num;
        for(uint256 i = 0; i < len; i++) {
            uint256 id = userBetMatchID[msg.sender][cupID][mID].at(i);
            if(!betInfo[cupID][id].isClaim) {
                uint256 value = IBallGame(betInfo[cupID][id].gameAddress).getClaim(cupID, mID, id);
                if(value > 0) {
                    betInfo[cupID][id].isClaim = true;
                    rewardPool.cliam(msg.sender, value);
                    emit Claim(msg.sender, cupID, id, value);
                    num++;
                }
            }
        }
        require(num > 0, "no claim");
    }

    function getUserCanClaim(
        address user, 
        uint256 cupID, 
        uint256 mID
    ) public view returns(uint256 value) {
        uint256 len = userBetMatchID[user][cupID][mID].length();
        if(len == 0) {
            return 0;
        }
        for(uint256 i = 0; i < len; i++) {
            uint256 id = userBetMatchID[user][cupID][mID].at(i);
            if(!betInfo[cupID][id].isClaim) {
                value = IBallGame(betInfo[cupID][id].gameAddress).getClaim(cupID, mID, id).add(value);
            }
        }
    }

    function checkClaim(address user, uint256 cupID, uint256 totalID) public view returns(uint256) {
        require(betInfo[cupID][totalID].user == user, "not yours");
        require(!betInfo[cupID][totalID].isClaim, "has claim");
        uint256 mID = betInfo[cupID][totalID].mID;
        require(matchInfo[cupID][mID].isCaculate, "can not claim");

        return IBallGame(betInfo[cupID][totalID].gameAddress).checkClaim(cupID, mID, totalID);
    }


    function caculateMatch(uint256 cupID, uint256 mID) external {
        checkCaculate(msg.sender, cupID, mID);
        matchInfo[cupID][mID].isCaculate = true;
        for(uint256 i = 0; i < midGameAddress[cupID][mID].length(); i++) {
            IBallGame(midGameAddress[cupID][mID].at(i)).caculateMatch(cupID, mID);
        }
        if(matchInfo[cupID][mID].hasBet) {
            notCacuNum--;
        }

        emit CaculateMatch(cupID, mID);
    }

    function checkCaculate(address account, uint256 cupID, uint256 mID) public view returns(bool) {
        _checkCacu(account);
        require(!matchInfo[cupID][mID].isCaculate, "has caculate");
        require(
            matchInfo[cupID][mID].isCancel || 
            (!matchInfo[cupID][mID].isCancel && matchInfo[cupID][mID].winType != 0),
            "not set result" 
        );

        return true;
    }

    event SetCancel(uint256 cupID, uint256 mID, bool isCancel);
    function setCancel(uint256 cupID, uint256 mID, bool isCancel) external {
        checkSetCancel(msg.sender, cupID, mID);
        matchInfo[cupID][mID].isCancel = isCancel;

        emit SetCancel(cupID, mID, isCancel);
    }

    function checkSetCancel(address account, uint256 cupID, uint256 mID) public view returns(bool) {
        _checkCacu(account);
        require(cupID > 0 && cupID <= totalCupID, "not exist");
        require(!matchInfo[cupID][mID].isCaculate, "has caculate");
        require(
            matchInfo[cupID][mID].startTime.add(matchInfo[cupID][mID].matchTime) < block.timestamp,
            "not end"
        );

        return true;
    }


    event SetResult(
        uint256 cupID,
        uint256 mID,
        uint256 aBall,
        uint256 bBall,
        uint8 result
    );
    function setResult(
        uint256 cupID,
        uint256 mID,
        uint256 aBall,
        uint256 bBall
    ) external {
        checkSetResult(msg.sender, cupID, mID);
        matchInfo[cupID][mID].homeGoals = aBall;
        matchInfo[cupID][mID].visitingGoals = bBall;
        if(aBall > bBall) {
            matchInfo[cupID][mID].winType = 1;
        } else if(aBall < bBall) {
            matchInfo[cupID][mID].winType = 2;
        } else {
            matchInfo[cupID][mID].winType = 3;
        }
        emit SetResult(cupID, mID, aBall, bBall, matchInfo[cupID][mID].winType);
    }

    function checkSetResult(
        address account,
        uint256 cupID,
        uint256 mID
    ) public view returns(bool) {
        _checkCacu(account);
        require(cupID > 0 && cupID <= totalCupID, "not exist");
        require(!matchInfo[cupID][mID].isCaculate, "has caculate");
        require(mID > 0 && mID <= matchID[cupID], "mID err");
        require(!matchInfo[cupID][mID].isCancel, "has set cancel");
        require(
            matchInfo[cupID][mID].startTime.add(matchInfo[cupID][mID].matchTime) < block.timestamp,
            "not end"
        );
        return true;
    }

    

    function setCaculateAccount(address account) external onlyOwner {
        caculateAccount = account;
    }

    function _checkCacu(address account) internal view {
        require(account == owner() || account == caculateAccount, "no auth");
    }

    function _checkAccount(address account) internal view {
        require(account == owner() || account == operator, "no auth");
    }

    function bet(
        address gameAddr,
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external {
        require(midGameAddress[cupID][mID].contains(gameAddr), "not in");
        require(amount >= cupInfo[cupID].minAmount &&  amount <= cupInfo[cupID].maxAmount, "out range");
        require(matchInfo[cupID][mID].isOpen, "game close");
        require(cupInfo[cupID].isPlay, "cup not open");
        uint256 totalID = ++cupInfo[cupID].totalBetID;
        (uint256 value, uint256 rate) = IBallGame(gameAddr).bet(cupID, mID, amount, index, choice);
        (uint256 bAmount, uint256 lAmount) = rewardPool.getTokenAmount(value, rate, baseRate, 1);
        if(!matchInfo[cupID][mID].hasBet) {
            matchInfo[cupID][mID].hasBet = true;
            ++notCacuNum;
        }

        if(!cupStatus[cupID].hasBet) {
            cupStatus[cupID].hasBet = true;
        }


        betInfo[cupID][totalID] = BetInfo(
            msg.sender,
            gameAddr,
            gameType[gameAddr],
            cupID,
            mID,
            amount,
            value,
            block.timestamp,
            rate,
            index,
            bAmount,
            lAmount,
            choice,
            true,
            false
        );
        userMatchID[msg.sender][cupID].add(mID);
        userBetID[msg.sender][cupID].add(totalID);
        userBetMatchID[msg.sender][cupID][mID].add(totalID);

        betToken.safeTransferFrom(msg.sender, address(rewardPool), amount);
        
        rewardPool.addMint(msg.sender, value, bAmount, lAmount);
        rewardPool.blast(msg.sender);
        nftPool.increaseMint(msg.sender, bAmount, lAmount);
        nftPool.gainExperience(msg.sender, value, 1);

        emit Bet(msg.sender, cupID, mID, totalID);
    }

    function setFeeRate(uint256 fee) external {
        require(fee >= 0 && fee < baseRate, "fee err");
        feeRate = fee;
    }


    function checkBet(
        address user,
        address gameAddr,
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external view returns(bool) {
        require(user != address(0), "user err");
        require(midGameAddress[cupID][mID].contains(gameAddr), "not in");
        require(amount >= cupInfo[cupID].minAmount &&  amount <= cupInfo[cupID].maxAmount, "out range");
        require(matchInfo[cupID][mID].isOpen, "game close");
        require(cupInfo[cupID].isPlay, "cup not open");
        return IBallGame(gameAddr).checkBet(cupID, mID, amount, index, choice);
    }



    function _checkMid(address gameAddr, uint256 cupID, uint256 mID) public view returns(bool) {
        require(enableGame.contains(gameAddr), "not in play");
        require(matchInfo[cupID][mID].startTime > block.timestamp, "has start");

        return true;
    }

    event SetMathIsOpen(uint256 cupID, uint256 mID, bool isOpen);
    function setMathIsOpen(uint256 cupID, uint256 mID, bool isOpen) external onlyOperator {
        require(matchInfo[cupID][mID].startTime > block.timestamp, "match has start");
        matchInfo[cupID][mID].isOpen = isOpen;

        emit SetMathIsOpen(cupID, mID, isOpen);
    }
    event AddMatch(
        uint256 cupID, 
        uint256 mID,
        uint256 homeTeam,
        uint256 visitingTeam,
        uint256 startTime,
        uint256 matchTime
    );

    function addMatch(
        uint256 cupID, 
        uint256 homeTeam,
        uint256 visitingTeam,
        uint256 startTime,
        uint256 matchTime,
        address[] memory gameAddr
    ) external {
        checkAddMatch(msg.sender, cupID, homeTeam, visitingTeam, startTime, matchTime, gameAddr);
        uint256 id = ++matchID[cupID];
        matchInfo[cupID][id].homeTeam = homeTeam;
        matchInfo[cupID][id].visitingTeam = visitingTeam;
        matchInfo[cupID][id].startTime = startTime;
        matchInfo[cupID][id].matchTime = matchTime;

        if(cupStatus[cupID].firstTime == 0) {
            cupStatus[cupID].firstTime = startTime;
        } else {
            if(cupStatus[cupID].firstTime > startTime) {
                cupStatus[cupID].firstTime = startTime;
            }
        }

        for(uint256 i = 0; i < gameAddr.length; i++) {
            midGameAddress[cupID][id].add(gameAddr[i]);
        }

        emit AddMatch(cupID, id, homeTeam, visitingTeam, startTime, matchTime);
    }

    function checkAddMatch(
        address account, 
        uint256 cupID, 
        uint256 homeTeam,
        uint256 visitingTeam,
        uint256 startTime,
        uint256 matchTime,
        address[] memory gameAddr
    ) public view returns(bool) {
        require(account == owner() || account == operator, "no auth");
        _check(cupID);
        require(
            teamID[cupID].contains(homeTeam) &&
            teamID[cupID].contains(visitingTeam) &&
            visitingTeam != homeTeam,
            "team id err"
        );
        require(
            startTime > block.timestamp &&
            startTime >= cupInfo[cupID].startTime &&
            startTime < cupInfo[cupID].endTime, 
            "time err"
        );
        require(matchTime > 0, "matchTime err");
        require(getIn(gameAddr), "game err");

        return true;
    }

    function getIn(address[] memory gameAddr) internal view returns(bool) {
        for(uint256 i = 0; i < gameAddr.length; i++) {
            if(!enableGame.contains(gameAddr[i])) {
                return false;
            }
        }
        return true;
    }

    function checkGame(address gameAddr, uint256 cupID, uint256 mID) public view returns(uint256) {
        _check(cupID);
        _checkMid(gameAddr, cupID, mID);

        return cupInfo[cupID].upRate;
    }

    function _check(uint256 cupID) internal view returns(bool) {
        require(cupID > 0 && cupID <= totalCupID, "not exist");
        require(cupInfo[cupID].endTime > block.timestamp, "has end");

        return true;
    }

    event AddOrRemoveTeam(uint256 cupID, uint256 tID, bool isAdd);

    function addOrRemoveTeam(uint256 cupID, uint256[] memory tID, bool isAdd) 
        external 
        onlyOperator 
        isExist(cupID)
        notStart(cupID)
    {

        if(isAdd) {
            for(uint256 i = 0; i < tID.length; i++) {
                if(teamID[cupID].length() == cupInfo[cupID].maxTeamNum) {
                    break;
                }
                require(!teamID[cupID].contains(tID[i]), "add repeat");
                require(tID[i] > 0 && tID[i] <= totalTeamID, "not exist");
                teamID[cupID].add(tID[i]);
                emit AddOrRemoveTeam(cupID, tID[i], isAdd);
            }
        } else {
            for(uint256 i = 0; i < tID.length; i++) {
                if(teamID[cupID].length() <= 2) {
                    break;
                }
                require(teamID[cupID].contains(tID[i]), "remove repeat");
                require(tID[i] > 0 && tID[i] <= totalTeamID, "not exist");
                teamID[cupID].remove(tID[i]);
                emit AddOrRemoveTeam(cupID, tID[i], isAdd);
            }
        }
    }

    function setMaxTeam(uint256 cupID, uint256 num) 
        external
        onlyOperator 
        isExist(cupID)
        notEnd(cupID)

    {
        require(num >= 2 && num > teamID[cupID].length(), "num err");
        cupInfo[cupID].maxTeamNum = num;
    }

    event SetCanPlay(uint256 cupID, bool isPlay);
    function setCanPlay(uint256 cupID, bool isPlay) 
        external 
        onlyOperator 
        isExist(cupID)
        notEnd(cupID)
    {
        cupInfo[cupID].isPlay = isPlay;

        emit SetCanPlay(cupID, isPlay);
    }

    function setEndTime(uint256 cupID, uint256 endTime) 
        external 
        onlyOperator 
        isExist(cupID)
        notEnd(cupID)
    {
        require(cupInfo[cupID].startTime < endTime && endTime > block.timestamp, "time err");
        cupInfo[cupID].endTime = endTime;
    }    

    function setStartTime(uint256 cupID, uint256 startTime) 
        external 
        onlyOperator 
        isExist(cupID)
        notStart(cupID)
    {
        require(
            startTime < cupInfo[cupID].endTime && startTime > block.timestamp, 
            "time err"
        );
        require(!cupStatus[cupID].hasBet, "some match has bet");
        require(cupStatus[cupID].firstTime > block.timestamp, "some match has start");
        cupInfo[cupID].startTime = startTime;
    }

    event SetCupName(uint256 cupID, string name);
    function setCupName(uint256 cupID, string memory name) 
        external 
        onlyOperator 
        isExist(cupID)
        notStart(cupID)
    {
        cupInfo[cupID].name = name;

        emit SetCupName(cupID, name);
    }


    event CreateCup(uint256 id);
    function createCup(CupInfo memory cInfo) external {
        checkCup(msg.sender, cInfo);
        cupInfo[++totalCupID] = cInfo;
        if(cInfo.endTime > lastTime) {
            lastTime = cInfo.endTime;
        }

        emit CreateCup(totalCupID);
    }

    function checkCup(address account, CupInfo memory cInfo) public view returns(bool) {
        require(account == owner() || account == operator, "no auth");
        require(cInfo.token == address(betToken), "token err");
        require(cInfo.upRate > baseRate, "upRate err");
        require(cInfo.maxTeamNum >= 2, "maxTeamNum err");
        require(cInfo.startTime > block.timestamp && cInfo.startTime < cInfo.endTime, "time err");
        require(cInfo.totalBetID == 0, "totalBetID err");
        require(cInfo.isPlay, "default play");

        return true;
    }
    
    function addOrRemoveGame(address gameAddr, bool isAdd) external onlyOperator {
        require(gameAddr != address(0), "not zero");
        if(isAdd) {
            require(!enableGame.contains(gameAddr), "has add");
            require(IBallGame(gameAddr).gameType() != 0, "type err");
            gameType[gameAddr] = IBallGame(gameAddr).gameType();
            unEnableGame.remove(gameAddr);
            enableGame.add(gameAddr);
        } else {
            require(enableGame.contains(gameAddr), "not in play");
            enableGame.remove(gameAddr);
            unEnableGame.add(gameAddr);
        }
    }

    function addTeam(string memory name, string memory site) external onlyOperator {
        uint256 id = ++totalTeamID;
        team[id].name = name;
        team[id].site = site; 

        emit AddTeam(id, name, site);
    }


    function setTeam(uint256 tID, string memory name, string memory site) external onlyOperator {
        require(tID > 0 && tID <= totalTeamID, "not exist");
        team[tID].name = name;
        team[tID].site = site; 

        emit SetTeam(tID, name, site);
    }


    function getChoiceRate(uint256 cupID, uint256 totalID) external view returns(int256, uint256, uint256) {
        return (betInfo[cupID][totalID].choice, betInfo[cupID][totalID].payRate, betInfo[cupID][totalID].value);
    }

    function getWinType(uint256 cupID, uint256 mID) external view returns(uint8) {
       return matchInfo[cupID][mID].winType;
    }

    function getResult(uint256 cupID, uint256 mID) external view returns(uint256, uint256) {
        return (matchInfo[cupID][mID].homeGoals, matchInfo[cupID][mID].visitingGoals);
    }

    function getIndex(uint256 cupID, uint256 totalID) external view returns(uint256) {
        return betInfo[cupID][totalID].index;
    }

    function getGType(uint256 cupID, uint256 totalID) external view returns(uint256, address) {
        return (betInfo[cupID][totalID].gType, betInfo[cupID][totalID].gameAddress);
    }
    
    function getCancle(uint256 cupID, uint256 mID) external view returns(bool) {
        return matchInfo[cupID][mID].isCancel;
    }

    // ****************************************************************
    function getTeamIDNum(uint256 cupID) external view returns(uint256) {
        return teamID[cupID].length();
    } 
    function getTeamID(uint256 cupID, uint256 index) external view returns(uint256) {
        return teamID[cupID].at(index);
    } 

    function getTotalGameNum(uint256 num) external view returns(uint256) {
        if(num == 1) {
            return enableGame.length();
        }

        if(num == 2) {
            return unEnableGame.length();
        }
        return 0;
    } 
    function getTotalGameAddr(uint256 num, uint256 index) external view returns(address) {
        require(num <= 2 && num > 0, "num err");
        if(num == 1) {
            return enableGame.at(index);
        } else {
            return unEnableGame.at(index);
        }
    } 

    function getMidGameAddressNum(uint256 cupID, uint256 mID) external view returns(uint256) {
        return midGameAddress[cupID][mID].length();
    }
    function getMidGameAddress(uint256 cupID, uint256 mID, uint256 index) external view returns(address) {
        return midGameAddress[cupID][mID].at(index);
    }

    function getUserIDNum(address user, uint256 cupID,uint256 num) external view returns(uint256) {
        if(num == 1) {
            return userMatchID[user][cupID].length();
        }

        if(num == 2) {
            return userBetID[user][cupID].length();
        }
        return 0;
    } 
    function getUserID(address user, uint256 cupID,uint256 num, uint256 index) external view returns(uint256) {
        require(num <= 2 && num > 0, "num err");
        if(num == 1) {
            return userMatchID[user][cupID].at(index);
        } else {
            return userBetID[user][cupID].at(index);
        }
    } 

    function getUserBetMatchIDNum(address user, uint256 cupID, uint256 mID) external view returns(uint256) {
        return userBetMatchID[user][cupID][mID].length();
    } 
    function getUserBetMatchID(address user, uint256 cupID, uint256 mID, uint256 index) external view returns(uint256) {
        return userBetMatchID[user][cupID][mID].at(index);
    } 


    function getInGame(address gameAddr) external view returns(bool) {
        if(enableGame.contains(gameAddr) || unEnableGame.contains(gameAddr)) {
            return true;
        }
        return false;
    }
    
    function getBetInfo(uint256 cupID, uint256 totalID) external view returns(BetInfo memory) {
        return betInfo[cupID][totalID];
    }

    function getEndInfo() external view returns(uint256, uint256) {
        return (lastTime, notCacuNum);
    }
 }