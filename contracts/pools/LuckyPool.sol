// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../../types/Ownable.sol";
import "../common/Auth.sol";
import "../../interfaces/ILuckyGame.sol";
import "../../interfaces/ILetDaoSwap.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/ILetDao.sol";

contract LuckyPool is Auth {
    event InitAsset(address account, uint256 amount);
    event AddAssets(address account, uint256 amount);
    event TransferTo(address token, address account, uint256 amount);
    event RewardDao(address dao, uint256 amount);
    event RewardPro(address pro, uint256 amount);
    event LuckyReward(address user, uint256 amount);
    event BnbGame(address account, address user, uint256 num);

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public immutable LET;
    IERC20 public immutable BET;
    IERC20 public immutable USDT;
    ILuckyGame public playGame;
    ILetDaoSwap public ldSwap;

    address public assetsAccount;
    address public proAccount;
    address public daoAccount;
    address public betUsdt;
    address public letUsdt;
    EnumerableSet.AddressSet betUser;

    uint256 public totalBetAmount;
    uint256 public daoAmount;
    uint256 public daoLetUserAmount;
    uint256 public daoLuckyAmount;
    uint256 public swapLetAmount;
    uint256 public swapBetAmount;
    uint256 public totalBAmount;
    uint256 public rewardAmount = 10e18;
    bool public isRank;
    bool public initTime;
    uint256 nonce;


    mapping(uint256 => EnumerableSet.AddressSet) users;
    mapping(uint256 => LuckeyUser) public luckeyUser;
    mapping (uint256 => address) public bnbUser;
    mapping(uint256 => uint256) public totalWeekAmount;
    mapping(uint256 => mapping(address => uint256)) public totalWeekUserAmount;
    mapping(uint256 => EnumerableSet.AddressSet) weekUser;
    mapping(address => mapping(uint256 => UserMint)) public userMint;
    mapping(address => mapping(uint256 => UserMint)) public userWeekMint;
    mapping(uint256 => BnbTime) public bnbTime;
    mapping(uint256 => mapping(address => uint256)) userTotalBet;
    mapping(address => uint256) public userBet;


    struct LuckeyUser {
        address user;
        uint256 amount;
    }

    struct UserMint {
        uint256 betAmount;
        uint256 letAmount;
    }

    struct BnbTime {
        uint256 startTime;
        uint256 actTime;
    }

    constructor(
        address letToken,
        address betToken,
        address usdt,
        address proAddr
    ) {
        require(address(0) != proAddr, "not zero address");

        USDT = IERC20(usdt);
        proAccount = proAddr;
        LET = IERC20(letToken);
        BET = IERC20(betToken);
    }

    function setRewardAmount(uint256 amount) external onlyOperator {
        require(amount > 0, "amount err");
        rewardAmount = amount;
    }

    function initBnbTime(uint256 startTime) external onlyOperator {
        require(!initTime, "has init");
        require(nob == 1, "nob err");
        require(startTime > block.timestamp, "time err");
        initTime = true;
        bnbTime[nob].startTime = startTime;
    }

    function setRate(
        uint256 initRate_,
        uint256 betLpRate_,
        uint256 letLpRate_,
        uint256 letUserRate_,
        uint256 pragmaRate_,
        uint256 luckyRate_      
    ) 
        external 
        onlyOperator 
    {
        uint256 num =  initRate_.add(betLpRate_).add(letLpRate_);
        num = num.add(letUserRate_).add(pragmaRate_).add(luckyRate_);
        require(num == baseRate, "out range");

        initRate = initRate_;
        betLpRate = betLpRate_;
        letLpRate = letLpRate_;
        letUserRate = letUserRate_;
        pragmaRate = pragmaRate_;
        luckyRate = luckyRate_;
    }

    modifier onlyAssets() {
        require(msg.sender == owner() || msg.sender == assetsAccount);
        _;
    }

    modifier onlyGame {
        require(msg.sender == address(playGame), "not playGame");
        _;
    }

    function setRank() external {
        require(msg.sender == daoAccount, "not dao contract");
        isRank = true;
    }

    function setAssetAccount(address account) external onlyOwner {
        assetsAccount = account;
    }

    function setLuckyGame(address account) external onlyOperator {
        playGame = ILuckyGame(account);
    }

    function setProAccount(address account) external onlyOperator {
        require(address(0) != account, "not zero address");

        proAccount = account;
    }

    function setDaoAccount(address account) external onlyOperator {
        daoAccount = account;
    }

    function setLP(address betUsdtLp, address letUsdtLp) external onlyOperator {
        betUsdt = betUsdtLp;
        letUsdt = letUsdtLp;
    }

    function setLetDaoSwap(address account) external onlyOperator {
        ldSwap = ILetDaoSwap(account);
    }

    function transferTo(address token, address account, uint256 amount) public onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "not enough");
        IERC20(token).safeTransfer(account, amount);
        
        emit TransferTo(token, account, amount);
    } 

    function initAssets() external onlyAssets {
        require(!isInit, "has init");

        isInit = true;
        _addAmount(initAmount);
        USDT.safeTransferFrom(msg.sender, address(this), initAmount);

        emit InitAsset(msg.sender, initAmount);
    }

    function addAssets(uint256 amount) external onlyAssets onlyInit {
        require(amount > 0, "amount err"); 

        _addAmount(amount);
        USDT.safeTransferFrom(msg.sender, address(this), amount);

        emit AddAssets(msg.sender, amount);
    }

    function _addAmount(uint256 amount) internal {
        poolInfo.totalAddAmount = poolInfo.totalAddAmount.add(amount);
        poolInfo.totalAmount = poolInfo.totalAmount.add(amount);
    }

    function addBetAmount(address user, uint256 amount) external onlyGame {
        poolInfo.totalAmount = poolInfo.totalAmount.add(amount);
        poolInfo.earnAmount = poolInfo.earnAmount.add(amount);

        if(poolInfo.totalAmount >= explosionAmount) {
            totalBAmount = totalBAmount.add(poolInfo.totalAmount);
            AllocateAssets();
            distReward();
            luckyReward();
            letSwap();
            betSwap();
            addAxplosionAmount();
            bnbUser[nob] = user;
            bnbTime[nob].actTime = block.timestamp;
            LET.mint(user, rewardAmount);

            emit BnbGame(address(this), user, nob);
            nob++;
            bnbTime[nob].startTime = block.timestamp;
        }
    }

    function addAxplosionAmount() internal {
        if(explosionAmount < upAmount) {
            explosionAmount = explosionAmount.add(addAmount);
        }
    }

    function userClaim(address user, uint256 amount) external onlyGame {
        poolInfo.totalAmount = poolInfo.totalAmount.sub(amount);
        poolInfo.loseAmount = poolInfo.loseAmount.add(amount);
        if(amount > 0) {
            USDT.safeTransfer(user, amount);
        }
    }

    function AllocateAssets() internal {
        bombInfo[nob].totalAmount = poolInfo.totalAmount;
        bombInfo[nob].nextInit = poolInfo.totalAmount.mul(initRate).div(baseRate);
        bombInfo[nob].betLp = poolInfo.totalAmount.mul(betLpRate).div(baseRate);
        bombInfo[nob].letLp = poolInfo.totalAmount.mul(letLpRate).div(baseRate);
        bombInfo[nob].letUserAmount = poolInfo.totalAmount.mul(letUserRate).div(baseRate);
        bombInfo[nob].proAmount = poolInfo.totalAmount.mul(pragmaRate).div(baseRate);

        uint256 lAmount = bombInfo[nob].nextInit.add(bombInfo[nob].betLp).add(bombInfo[nob].letLp);
        lAmount = lAmount.add(bombInfo[nob].letUserAmount).add(bombInfo[nob].proAmount);

        bombInfo[nob].luckyAmount = poolInfo.totalAmount.sub(lAmount);
        poolInfo.totalAmount = bombInfo[nob].nextInit;
    }

    function distReward() internal {
        daoLetUserAmount = daoLetUserAmount.add(bombInfo[nob].letUserAmount);

        if(daoAccount != address(0)) {
            if(daoLetUserAmount > 0 && ILetDao(daoAccount).voteInfo(address(this)) > 0) {
                uint256 value = daoLetUserAmount;
                daoLetUserAmount = 0;
                ILetDao(daoAccount).addBNB(address(this), nob, value);
                USDT.safeTransfer(daoAccount, value);

                emit RewardDao(daoAccount, value);
            }
        } else {
            if(daoLetUserAmount > 0) {
                uint256 value = daoLetUserAmount;
                daoLetUserAmount = 0;
                USDT.safeTransfer(proAccount, value);
                emit RewardPro(proAccount, value);
            }
        }

        if(bombInfo[nob].proAmount > 0) {
            USDT.safeTransfer(proAccount, bombInfo[nob].proAmount);
            emit RewardPro(proAccount, bombInfo[nob].proAmount);
        }
    }

    function letSwap() internal {
        swapLetAmount = swapLetAmount.add(bombInfo[nob].letLp);

        if(address(ldSwap) != address(0)) {
            if(swapLetAmount > 0 && letUsdt != address(0)) {
                uint256 _let = swapLetAmount;
                swapLetAmount = 0;
                USDT.safeIncreaseAllowance(address(ldSwap), _let);
                address[] memory path_ = new address[](2);
                path_[0] = address(USDT); 
                path_[1] = address(LET);
                ldSwap.depositSigleToken(letUsdt, path_, _let, 0, 0, block.timestamp.add(24 hours));
            }
        }
    }

    function betSwap() internal {
        swapBetAmount = swapBetAmount.add(bombInfo[nob].betLp);

        if(address(ldSwap) != address(0)) {
            if(swapBetAmount > 0 && betUsdt != address(0)) {
                uint256 _bet = swapBetAmount;
                swapBetAmount = 0;

                USDT.safeIncreaseAllowance(address(ldSwap), _bet);
                address[] memory path_ = new address[](2);
                path_[0] = address(USDT); 
                path_[1] = address(BET);
                ldSwap.depositSigleToken(betUsdt, path_, _bet, 0, 0, block.timestamp.add(24 hours));
            }
        }
    }
 
    function luckyReward() internal {
        address user = getLucker(nob);
        if(user == address(0)) {
            user = proAccount;
        }
        luckeyUser[nob].user = user;

        if(bombInfo[nob].luckyAmount > 0) {
            luckeyUser[nob].amount = bombInfo[nob].luckyAmount;
            USDT.safeTransfer(user, bombInfo[nob].luckyAmount);
            emit LuckyReward(user, bombInfo[nob].luckyAmount);
        }
    }


    function getLucker(uint256 nob) internal returns(address) {
        uint256 len = users[nob].length();
        if(len > 0) {
            uint256 number = 
            uint256(keccak256(abi.encodePacked(
                block.timestamp,
                msg.sender,
                address(this),
                nonce,
                block.number
            ))).mod(len);

            nonce++;
            return users[nob].at(number);
        }
        return address(0);
    }


    function getTotalAmount() external view returns(uint256) {
        return poolInfo.totalAmount;
    }

    function getUserLength(uint256 num) external view returns(uint256) {
        return users[num].length();
    }

    function getUserAddr(uint256 num, uint256 index) external view returns(address, uint256) {
        address user = users[num].at(index);
        return (user, userTotalBet[num][user]); 
    }

    function getUserContains(uint256 num, address user) external view returns(bool) {
        return users[num].contains(user);
    }

    function getBetAmount(uint256 num, address user) external view returns(uint256) {
        return userTotalBet[num][user];
    }

    function updateWeek() public {
        if(address(0) != daoAccount) {
            ILetDao(daoAccount).updateWeek();
        }
    }

    function getWeekUserNum(uint256 wID) external view returns(uint256) {
        return weekUser[wID].length();
    }

    function getWeekUser(uint256 wID, uint256 index) external view returns(address, uint256) {
        address user = weekUser[wID].at(index);
        return (user, totalWeekUserAmount[wID][user]);
    }

    function getWeekUserIn(uint256 wID, address user) external view returns(bool) {
        return weekUser[wID].contains(user);
    }


    function addMint(address user, uint256 amount, uint256 bAmount, uint256 lAmount) external onlyGame {
        users[nob].add(user);
        betUser.add(user);
        userBet[user] = userBet[user].add(amount);
        totalBetAmount = totalBetAmount.add(amount);
        userTotalBet[nob][user] = userTotalBet[nob][user].add(amount);
        userMint[user][nob].betAmount = userMint[user][nob].betAmount.add(bAmount);
        userMint[user][nob].letAmount = userMint[user][nob].letAmount.add(lAmount);

        if(isRank && address(0) != daoAccount) {
            uint256 wID = ILetDao(daoAccount).weekID();
            totalWeekAmount[wID] = totalWeekAmount[wID].add(amount);
            totalWeekUserAmount[wID][user] = totalWeekUserAmount[wID][user].add(amount);
            weekUser[wID].add(user);
            
            userWeekMint[user][wID].betAmount = userWeekMint[user][wID].betAmount.add(bAmount);
            userWeekMint[user][wID].letAmount = userWeekMint[user][wID].letAmount.add(lAmount);
        }
    }



    function setExplosionAmount(uint256 amount) external onlyOperator {
        require(amount > poolInfo.totalAmount, "amount err");
        explosionAmount = amount;
    }

    function getBnbNum() public view returns(uint256) {
        return nob - 1;
    }

    function getBnbAveTime() external view returns(uint256) {
        if(nob == 1) {
            return 0;
        }
        return bnbTime[getBnbNum()].actTime.sub(bnbTime[1].startTime).div(getBnbNum());
    }

    function getBetUserNum() external view returns(uint256) {
        return betUser.length();
    }

    function getBetUser(uint256 index) external view returns(address) {
        return betUser.at(index);
    }
}