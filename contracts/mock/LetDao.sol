// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IERC721.sol";
import "../common/Op.sol";
import "../../interfaces/ILuckyGame.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/IExp.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/IPlayerNFT.sol";
import "../../types/ReentrancyGuard.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/IUniswapV2Pair.sol";

contract LetDao is Op, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Deposit(address user, address token, uint256 amount, uint256 vLet, uint256 timeid);
    event Withdraw(address user, address token, uint256 amount, uint256 wID, uint256 timeid);
    event Vote(address user, address gamePool, uint256 beforeAmount, uint256 afterAmount);
    event ClaimReward(address gamePool, address user, uint256 nob, uint256 amount);
    event AddBNB(address gamePool, uint256 nob, uint256 amount);
    event NewWeek(uint256 wID, uint256 startTime);
    event AddLPToken(address lpToken, uint256 increase);

    IERC20 public USDT;
    IERC20 public LET;
    IERC20 public BET;
    EnumerableSet.AddressSet pools;

    uint256 public timeID;
    uint256 public voteTime = 7 days;
    uint256 public totalVeLet;
    uint256 public constant muti = 1e18;
    uint256 public lpID;

    uint256 public weekID;
    uint256 public periodTime = 7 days;
    uint256 public nextWeekStartTime;
    uint256 weekIndex;
    uint256 public initTime;
    address[] waitPool;
    address[] rankPool;

    struct UserTokenInfo {
        address token;
        uint256 amount;
        uint256 veLet;
        uint256 lastTime;
        uint256 timeID;
    }


    struct WightInfo {
        uint256 time;
        uint256 weight;
        uint256 veLet;
    }

    struct LPInfo {
        address lpToken;
        uint256 increase;
        bool isDeposit;
    }

    struct UserInfo{
        uint256 veLet;
    }

    struct UserVoteInfo {
        address gamePool;
        uint256 tickets;
        uint256 voteTime;
    }

    struct VoteInfo {
        uint256 totalTickets;
    }

    struct BnbReward {
        uint256 totalVotes;
        uint256 amount;
        uint256 perAmount;
        uint256 totalNum;
        uint256 cliamNum;
    }

    struct UserReward {
        uint256 amount;
        uint256 time;
    }

    struct UserRInfo {
        uint256 haveClaim;
        uint256[] haveNob;
    }

    struct WeekInfo {
        uint256 startTime;
        uint256 endTime;
        address[] weekPool;
    }

    struct Decay {
        uint256 decay;
        uint256 base;
    }


    mapping(address => mapping(uint256 => mapping(address => UserTokenInfo))) public userTokenInfo;
    mapping(address => mapping(uint256 => uint256)) public withdrawNum;
    mapping(address => mapping(uint256 => mapping(uint256 => UserTokenInfo[]))) public withdrawInfo;

    mapping(uint256 => LPInfo) public lpInfo;
    mapping(address => uint256) public lpToID;
    mapping(uint256 => mapping(address => uint256)) public tokenTotalAmount;
    mapping(address => uint256) public totalAmount;

    mapping(uint256 => Decay) decay;
    mapping(uint256 => WeekInfo)  weekInfo;
    mapping(uint256 => address[]) weekPool;
    mapping(address => mapping(address => UserRInfo)) userRInfo;
    mapping(address => mapping(address => mapping(uint256 => UserReward))) public userReward;
    mapping(address => mapping(address => uint256)) claimNum;
    mapping(address => mapping(address => mapping(uint256 => uint256[]))) userCNob;

    mapping(address => UserVoteInfo) public userVoteInfo;
    mapping(address => VoteInfo) public voteInfo;

    mapping(address => mapping(address => bool)) public isInPool;
    mapping(address => mapping(address => uint256)) public userPoolIndex;
    mapping(address => address[]) public gameVoteUser;
    mapping(address => mapping(uint256 => BnbReward)) public bnbReward;
    mapping(address => mapping(uint256 => address[])) public gameNobUser;
    mapping(address => mapping(address => uint256)) public userNob;

    mapping(uint256 => WightInfo) public wightInfo;
    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet)) userBetToken;
    mapping(address => EnumerableSet.UintSet) userBetTimeID;
    mapping(address => uint256) public userTotalVeLet;
    mapping(address => mapping(address => EnumerableSet.UintSet)) userGameNob;
    mapping(uint256 => mapping(address => uint256)) public weekGameVote;


    constructor(
        address usdt,
        address betToken,
        address letToken,
        uint256 startTime
    ) {
        require(startTime > block.timestamp, "start time err");
        USDT = IERC20(usdt);
        BET = IERC20(betToken);
        LET = IERC20(letToken);
        _init();
        nextWeekStartTime = startTime;
        initTime = startTime;
        setDecay();
    }

    function setVoteTime(uint256 time) external onlyOperator {
        voteTime = time;
    }

    function setTime(uint256 time) external onlyOperator {
        require(initTime > block.timestamp,"not set");
        require(initTime == nextWeekStartTime, "not same");
        require(time > block.timestamp, "time err");
        initTime = time;
        nextWeekStartTime = initTime;
    }

    function setWightTime(
        uint256[] memory times
    ) external onlyOperator {
        checkTimes(times);
        for(uint256 i = 1; i <= times.length; i++) {
            _setTime(i, times[i]);
        }
    }

    function setPeriodTime(uint256 time) external onlyOperator {
        require(time > 0, "time err");
        periodTime = time;
    }

    function addGamePool(address gamePool) external onlyOperator {
        require(address(0) != gamePool, "not zero address");
        require(!pools.contains(gamePool), "has add");
        updateWeek();
        pools.add(gamePool);
        waitPool.push(gamePool);
    }


    function deposit(uint256 amount, uint256 timeid) external nonReentrant {
        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _updateNob(userVoteInfo[msg.sender].gamePool, msg.sender);
        }

        uint256 vLet = checkDeposit(amount, timeid);

        _deposit(address(LET), amount, timeid, vLet);       
    }

    function getWithdrawInfoNum(address user, uint256 timeid, uint256 wNum) external view returns(uint256) {
        return withdrawInfo[user][timeid][wNum].length;
    }

    function getWithdrawInfo(address user, uint256 timeid, uint256 wNum) external view returns(UserTokenInfo[] memory) {
        return withdrawInfo[user][timeid][wNum];
    } 

    function _deposit(address token, uint256 amount, uint256 timeid, uint256 vLet) internal {
            
        userBetTimeID[msg.sender].add(timeid);
        userBetToken[msg.sender][timeid].add(token);
        userTokenInfo[msg.sender][timeid][token].token = token;
        userTokenInfo[msg.sender][timeid][token].amount += amount;
        userTokenInfo[msg.sender][timeid][token].timeID = timeid;
        userTokenInfo[msg.sender][timeid][token].veLet += vLet;
        userInfo[msg.sender][timeid].veLet += vLet;
        userTokenInfo[msg.sender][timeid][token].lastTime = block.timestamp;
        tokenTotalAmount[timeid][token] += amount;
        totalAmount[token] += amount;
        totalVeLet = totalVeLet.add(vLet);
        userTotalVeLet[msg.sender] = userTotalVeLet[msg.sender].add(vLet);

        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _vote(userVoteInfo[msg.sender].gamePool);
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, token, amount, vLet, timeid);
    }

    function withdraw(address token, uint256 timeid) external nonReentrant {
        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _updateNob(userVoteInfo[msg.sender].gamePool, msg.sender);
        }

        checkWithdraw(msg.sender, token, timeid);
  
        uint256 wID = withdrawNum[msg.sender][timeid];
        {
            tokenTotalAmount[timeid][token] -= userTokenInfo[msg.sender][timeid][token].amount;
            totalAmount[token] -= userTokenInfo[msg.sender][timeid][token].amount;
            totalVeLet -= userTokenInfo[msg.sender][timeid][token].veLet;
            userTotalVeLet[msg.sender] -= userTokenInfo[msg.sender][timeid][token].veLet;

            IERC20(token).safeTransfer(msg.sender, userTokenInfo[msg.sender][timeid][token].amount);
            withdrawInfo[msg.sender][timeid][wID].push(userTokenInfo[msg.sender][timeid][token]);

            emit Withdraw(msg.sender, token, userTokenInfo[msg.sender][timeid][token].amount, wID, timeid);
            delete userTokenInfo[msg.sender][timeid][token];
        }

        userBetToken[msg.sender][timeid].remove(token);
        if(userBetToken[msg.sender][timeid].length() == 0) {
            userBetTimeID[msg.sender].remove(timeid);
        }

        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _vote(userVoteInfo[msg.sender].gamePool);
        }
    }

    function vote(address gamePool) external nonReentrant {
        checkVote(msg.sender, gamePool);

        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _updateNob(userVoteInfo[msg.sender].gamePool, msg.sender);
        }

        if(
            userVoteInfo[msg.sender].gamePool != address(0) && 
            userVoteInfo[msg.sender].gamePool != address(gamePool)) 
        {
            address _gamePool = userVoteInfo[msg.sender].gamePool;
            voteInfo[_gamePool].totalTickets = voteInfo[_gamePool].totalTickets.sub(userVoteInfo[msg.sender].tickets);
            userVoteInfo[msg.sender].tickets = 0;

            removeUser(_gamePool, msg.sender);
            leaveNob(_gamePool);
            _vote(gamePool);

            emit Vote(msg.sender, userVoteInfo[msg.sender].gamePool, userVoteInfo[msg.sender].tickets, 0);
        } else {
            _vote(gamePool);
        }
        userVoteInfo[msg.sender].voteTime = block.timestamp;
    }


   
    function updateWeek() public {
        if(initTime > block.timestamp) {
            if(weekIndex == 0) {
                ++weekIndex;
                weekID = weekIndex - 1;
            }
            weekInfo[weekID].startTime = nextWeekStartTime;
            _update();
        }

        if(block.timestamp > nextWeekStartTime.add(periodTime)) {
            nextWeekStartTime = block.timestamp;
            if(weekInfo[weekID].startTime != 0) {
                weekInfo[weekID].endTime = nextWeekStartTime;
            }
            for(uint256 i = 0; i < rankPool.length; i++) {
                if(weekIndex != 0) {
                    weekGameVote[weekID][rankPool[i]] = voteInfo[rankPool[i]].totalTickets;
                }
            }


            ++weekIndex;
            weekID = weekIndex - 1;
            setDecay();
 
            weekInfo[weekID].startTime = nextWeekStartTime;

            _update();

            emit NewWeek(weekID, nextWeekStartTime);
        }
    }

    function _update() internal {
        uint256 len = waitPool.length;
        if(len > 0) {
            for(uint256 i = 0; i < len; i++) {
                IPool(waitPool[i]).setRank();
                rankPool.push(waitPool[i]);
            }
            for(uint256 i = 0; i < len; i++) {
                waitPool.pop();
            }
        }
        weekInfo[weekID].weekPool = rankPool;
    }


    function updateNob(address gamePool, address user) public {
        require(userVoteInfo[user].gamePool == gamePool && gamePool != address(0), "gamePool err");
        require(userVoteInfo[user].tickets > 0, "no vote");
        _updateNob(gamePool, user);
    }

    function _updateNob(address gamePool, address user) internal {
        uint256 num = getUserBnbNobNum(gamePool, user);
        uint256 num1 = ++claimNum[gamePool][user];
        if(num > 0) {
            for(uint256 i = 0; i < num; i++) {
                uint256 nob =  getUserBnbNob(gamePool, user, i);
                userCNob[gamePool][user][num1].push(nob);
                userGameNob[gamePool][user].add(nob);
                _claimReward(gamePool, user, nob);
            }

            userNob[gamePool][user] = IPool(gamePool).nob();
        }
    }

    function inNob(address gamePool) internal {
        uint256 nob = IPool(gamePool).nob();
        if(userNob[gamePool][msg.sender] == 0) {
            userNob[gamePool][msg.sender] = nob;
        }
    }

    function leaveNob(address gamePool) internal {
        userNob[gamePool][msg.sender] = 0;
    }

    function getUserInBnbNob(address gamePool, address user, uint256 nob) public view returns(bool) {
        if(userGameNob[gamePool][user].contains(nob)) {
            return true;
        }

        if(userNob[gamePool][user] <= nob && nob < IPool(gamePool).nob()) {
            return true;
        }

        return false;
    }

    function getUserBnbNobNum(address gamePool, address user) public view returns(uint256) {
        return IPool(gamePool).nob().sub(userNob[gamePool][user]);
    }

    function getUserBnbNob(
        address gamePool, 
        address user, 
        uint256 index
    ) internal view returns(uint256) {
        uint256 nob = userNob[gamePool][user].add(index);
        if(nob > IPool(gamePool).nob()) {
            return 0;
        }

        return nob;
    }

    function _vote(address gamePool) internal {
        uint256 beforeAmount = userVoteInfo[msg.sender].tickets;
        voteInfo[gamePool].totalTickets = voteInfo[gamePool].totalTickets.add(userTotalVeLet[msg.sender]).sub(beforeAmount); 

        addUser(gamePool, msg.sender);
        userVoteInfo[msg.sender].gamePool = gamePool;
        userVoteInfo[msg.sender].tickets = userTotalVeLet[msg.sender];

        inNob(gamePool);

        emit Vote(msg.sender, gamePool, beforeAmount, userVoteInfo[msg.sender].tickets);
    }



    function _claimReward(address gamePool, address user, uint256 nob) internal {
        uint256 amount = userVoteInfo[user].tickets.mul(bnbReward[gamePool][nob].perAmount).div(muti);
        userRInfo[gamePool][user].haveClaim = userRInfo[gamePool][user].haveClaim.add(amount);
        userRInfo[gamePool][user].haveNob.push(nob);
        
        ++bnbReward[gamePool][nob].cliamNum;
        userReward[gamePool][user][nob].time = block.timestamp;
        userReward[gamePool][user][nob].amount = amount;

        USDT.safeTransfer(user, amount);

        emit ClaimReward(gamePool, user, nob, amount);
    }

    function addBNB(address gamePool, uint256 nob, uint256 amount) external {
        require(pools.contains(gamePool), "not add pool");

        gameNobUser[gamePool][nob] = gameVoteUser[gamePool];
        bnbReward[gamePool][nob].totalVotes = voteInfo[gamePool].totalTickets;
        bnbReward[gamePool][nob].amount = amount;
        bnbReward[gamePool][nob].perAmount = amount.mul(muti).div(voteInfo[gamePool].totalTickets);
        bnbReward[gamePool][nob].totalNum = gameNobUser[gamePool][nob].length;

        emit AddBNB(gamePool, nob, amount);
    }



    function checkVote(address user, address gamePool) public view returns(bool) {
        require(pools.contains(gamePool), "gamePool not add");
        require(userTotalVeLet[user] > 0, "userTotalVeLet err");
        if(userVoteInfo[user].voteTime != 0) {
            require(block.timestamp > userVoteInfo[user].voteTime.add(voteTime), "vote time err");
        }

        return true;
    }

    function getUnlockTime(address user, address token, uint256 timeid) external view returns(uint256) {
        if(userTokenInfo[user][timeid][token].lastTime == 0) {
            return 0;
        }
        return userTokenInfo[user][timeid][token].lastTime.add(wightInfo[timeid].time);
    }


    function checkWithdraw(address user, address token, uint256 timeid) public view returns(bool) {
        require(0 < timeid && timeid <= 5, "timeid err");
        require(userBetToken[user][timeid].contains(token), "no deposit");
        require(
            userTokenInfo[user][timeid][token].lastTime.add(wightInfo[timeid].time) < block.timestamp, 
            "not claim time"
        );

        return true;
    }

    function checkDeposit(uint256 amount, uint256 timeid) public view returns(uint256) {
        require(amount > 0, "amount err");
        require(0 < timeid && timeid <= 5, "timeid err");
        return _check(amount, timeid);
    }

    function _check(uint256 amount, uint256 timeid) internal view returns(uint256) {
        uint256 vLet = amount.mul(wightInfo[timeid].weight).div(baseRate);
        require(vLet > 0, "amount to less");

        return vLet;
    }


    function _init() internal {
        _setTime(++timeID, 1 weeks, 50);
        _setTime(++timeID, 30 days, 200);
        _setTime(++timeID, 6 * 30 days, 1300);
        _setTime(++timeID, 12 * 30 days, 2500);
        _setTime(++timeID, 4 * 12 * 30 days, 10000);
    }

    function checkTimes(uint256[] memory times) public pure returns(bool) {
        require(times.length == 5, "length err");
        require(_checkQueue(times), "time err");

        return true;
    }

    function _checkQueue(uint256[] memory times) public pure returns(bool) {
        for(uint256 i = 0; i < times.length - 1; i++) {
            if(times[i] > times[i+1]) {
                return false;
            }
        }

        return true;
    }

    function _setTime(uint256 id, uint256 time) internal {
        wightInfo[id].time = time;
    }

    function _setTime(uint256 id, uint256 time, uint256 weight) internal {
        wightInfo[id].time = time;
        wightInfo[id].weight = weight;
    }


    function getGameVoteUserNum(address gamePool) external view returns(uint256) {
        return gameVoteUser[gamePool].length;
    }

    function getGameVoteUser(address gamePool) external view returns(address[] memory) {
        return gameVoteUser[gamePool];
    }  

    function getGameNobUserNum(address gamePool, uint256 nob) external view returns(uint256) {
        return gameNobUser[gamePool][nob].length;
    }

    function getGameNobUser(address gamePool, uint256 nob) external view returns(address[] memory) {
        return gameNobUser[gamePool][nob];
    }


    function getWeekPoolNum(uint256 wID) external view returns(uint256) {
        return weekInfo[wID].weekPool.length;
    }

    function getWeekInfo(uint256 wID) external view returns(WeekInfo memory) {
        return weekInfo[wID];
    }

    function getWeekPool(uint256 wID) external view returns(address[] memory) {
        return weekInfo[wID].weekPool;
    }

    function getRankPoolNum() external view returns(uint256) {
        return rankPool.length;
    }

    function getRankPool() external view returns(address[] memory) {
        return rankPool;
    }

    function getWaitPoolNum() external view returns(uint256) {
        return waitPool.length;
    }

    function getWaitPool() external view returns(address[] memory) {
        return waitPool;
    }

    function getPoolGame(address gemaPool) public view returns(address) {
        return IPool(gemaPool).playGame();
    }

    uint256 maxWeek = 12;
    function setDecay() internal {
        if(weekID == 0) {
            decay[weekID].decay = 1;
            decay[weekID].base = 1;
        } else {
            if(weekID <= maxWeek) {
                decay[weekID].decay = decay[weekID-1].decay.mul(85);
                decay[weekID].base = decay[weekID-1].base.mul(100);  
            } else {
                decay[weekID].decay = decay[maxWeek].decay;
                decay[weekID].base = decay[maxWeek].base;
            }
        }
    }

    function getDecay(uint256 wID) external view returns(uint256, uint256) {
        require(wID <= weekID, "wID err");

        return (decay[wID].decay, decay[wID].base);
    }

    function getGamePoolNum() external view returns(uint256) {
        return pools.length();
    }

    function getGamePool(uint256 index) external view returns(address) {
        return pools.at(index);
    }

    function getUserCanVoteTime(address user) external view returns(uint256) {
        uint256 time = userVoteInfo[user].voteTime.add(voteTime);
        uint256 bTime = block.timestamp;
        if(bTime <= time) {
            return time - bTime;
        }
        return 0;
    }

    function getLPInfo(address lpToken) external view returns(LPInfo memory) {
        return lpInfo[lpToID[lpToken]];
    }
 
    function addLPToken(address lpToken, uint256 increase) external  {
        checkAddLPToken(msg.sender, lpToken, increase);
        lpToID[lpToken] = ++lpID;
        lpInfo[lpID].lpToken = lpToken;
        lpInfo[lpID].increase = increase;
        lpInfo[lpID].isDeposit = true;

        emit AddLPToken(lpToken, increase);
    }


    function depositLPToken(address lpToken, uint256 amount, uint256 timeid) external nonReentrant {
        if(userVoteInfo[msg.sender].gamePool != address(0)) {
            _updateNob(userVoteInfo[msg.sender].gamePool, msg.sender);
        }

        uint256 vLet = checkDepositLPToken(lpToken, amount, timeid);
        _deposit(lpToken, amount, timeid, vLet);
    }

    function checkDepositLPToken(
        address lpToken, 
        uint256 amount, 
        uint256 timeid
    ) public view returns(uint256) {
        uint256 lID = lpToID[lpToken];
        require(lID != 0, "not add");
        require(lpInfo[lpID].isDeposit, "can not deposit");
        require(amount > 0, "amount err");
        require(0 < timeid && timeid <= 5, "timeid err");
        uint256 lAmount;
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(lpToken).getReserves();
        if(IUniswapV2Pair(lpToken).token0() == address(LET)) {
            lAmount = reserve0;
        } else {
            lAmount = reserve1;
        }

        uint256 total = IUniswapV2Pair(lpToken).totalSupply();
        uint256 value = amount.mul(2).mul(lAmount);
        value = value.mul(wightInfo[timeid].weight).mul(lpInfo[lpID].increase);
        uint256 vLet = value.div(total).div(baseRate).div(baseRate);
        require(vLet > 0, "amount to less");

        return vLet;
    }

    function setLPEnable(address lpToken, bool isDeposit) external onlyOperator {
        uint256 lID = lpToID[lpToken];
        require(lID != 0, "not add");
        lpInfo[lID].isDeposit = isDeposit;
    }

    function setLPIncrease(address lpToken, uint256 increase) external onlyOperator {
        uint256 lID = lpToID[lpToken];
        require(lID != 0, "not add");
        require(increase > 10000, "increase err");
        lpInfo[lpID].increase = increase;     
    }
 
    function checkAddLPToken(
        address user, 
        address lpToken, 
        uint256 increase
    ) public view returns(bool) {
        require(user == owner() || user == operator, "no permission");
        require(lpToID[lpToken] == 0, "has add");
        require(
            IUniswapV2Pair(lpToken).token0() == address(LET) || 
            IUniswapV2Pair(lpToken).token1() == address(LET),
            "lpToken err"
        );
        require(increase > 10000, "increase err");


        return true;
    }


    function getVoteReward(address user) external view returns(address gamePool, uint256 amount) {
        gamePool = userVoteInfo[user].gamePool;
        if(gamePool != address(0)) {
            uint256 num = getUserBnbNobNum(gamePool, user);
            if(num > 0) {
                for(uint256 i = 0; i < num; i++) {
                    uint256 nob =  getUserBnbNob(gamePool, user, i);
                    amount = userVoteInfo[user].tickets.mul(bnbReward[gamePool][nob].perAmount).div(muti).add(amount);
                }
            }
        }
    }


    function getUserBetTokenNum(address user, uint256 timeid) external view returns(uint256) {
        return userBetToken[user][timeid].length();  
    }

    function getUserBetToken(address user, uint256 timeid, uint256 index) external view returns(address) {
        return userBetToken[user][timeid].at(index);  
    }


    function getUserBetTimeIDNum(address user) external view returns(uint256) {
        return userBetTimeID[user].length();
    }

    function getUserBetTimeID(address user, uint256 index) external view returns(uint256) {
        return userBetTimeID[user].at(index);
    }

    function getUserCNob(address gamePool, address user, uint256 num) external view returns(uint256[] memory) {
        return userCNob[gamePool][user][num];
    }


    function getUserHasClaimNum(address gamePool, address user) external view returns(uint256) {
        return userGameNob[gamePool][user].length();
    }

    function getUserHasClaimNob(address gamePool, address user, uint256 index) external view returns(uint256) {
        return userGameNob[gamePool][user].at(index);
    }

    function addUser(address gamePool, address user) internal {
        if(!isInPool[gamePool][user]) {
            isInPool[gamePool][user] = true;
            uint256 index = gameVoteUser[gamePool].length;
            userPoolIndex[gamePool][user] = index;
            gameVoteUser[gamePool].push(user);
        }
    }

    function removeUser(address gamePool, address user) internal {
        if(isInPool[gamePool][user]) {
            if(gameVoteUser[gamePool].length > 1) {
                isInPool[gamePool][user] = false;

                uint256 index = userPoolIndex[gamePool][user];
                uint256 lastIndex = gameVoteUser[gamePool].length - 1;
                if(index != lastIndex) {
                    address lastUser = gameVoteUser[gamePool][lastIndex];

                    userPoolIndex[gamePool][lastUser] = index;
                    gameVoteUser[gamePool][index] = lastUser;
                }

            }
            gameVoteUser[gamePool].pop();
        }
    }   
}