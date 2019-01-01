pragma solidity ^0.4.25;
contract soccerBet {
    //合约所有者
    address private owner = address(0x0);
    //合约状态
    bool private gameActive = true;
    //管理员
    address[] private admins;
    //合约分成百分比
    uint8 private commission = 0;
    
    //竞猜状态
    enum GameStatus { original, open, close, setScore, withdrawed }   //竞猜刚创建,竞猜打开，竞猜关闭，已结束设置比分, 已派奖
    //比赛结果
    enum GameResult { original, hostTeamWin, equal, guestTeamWin }
    //比分
    struct GameScore {
        uint8 hostScore;
        uint8 guestScore;
    }
    //比赛信息
    struct GameInfo {
        string hostTeam;            //主队
        string guestTeam;           //客队
        uint createTime;            //竞猜创建时间
        uint stopBetTime;           //竞猜终止时间
        int8 point;                 //让球,传入参数是实际让球100倍兼容小数让球,主队让球为负
    }
    //玩家投注信息
    struct BetInfo {
        uint betPlayerCount;        //玩家人数
        uint betHostWinAmout;       //投注主队胜金额
        uint betGuestWinAmout;      //投注客队胜金额
        uint betEqualAmout;         //投注平局金额
        uint totalBetAmount;        //总投注金额
    }
    
    //投注玩家
    struct BetPlayer {
        address addr;           //投注地址
        uint amount;            //投注金额
        GameResult betStatus;   //投注胜负平状态
        bool draw;              //是否发奖金
    }
    
    uint private minimalBet = 1 ether;          //最小投注金额 
    uint private maxBet = 10000 ether;          //玩家最大投注金额
    uint private totalBetLimit = 100000 ether;  //每场比赛最大投注金额
    
    //足球竞猜游戏
    struct SoccerGame {
        GameStatus status;          //竞猜状态
        GameInfo gameInfo;          //竞猜比赛信息
        
        GameScore gameScore;        //比分
        GameResult result;          //让球后比赛结果
        
        BetInfo betInfo;            //下注信息
        mapping (uint => BetPlayer) betPlayerMapping;   //投注玩家 (玩家索引=>玩家）
        
        address whoCreated;
        address whoSetScore;
        address whoWithDraw;
    }
    
    mapping ( uint => SoccerGame ) gameMapping;     //比赛映射表
    uint[] unWithdrawGameId;                        //未分配奖金比赛
    
    //event
    event createGameEvent(uint _gameId, address _admin, string _hostTeam, string _guestTeam, int8 _rqPoint, uint _stopBetTime);
    event openGameEvent(uint _gameId, address _admin);
    event stopBetEvent(uint _gameId, address _admin);
    event playerBetEvent(uint _gameId, uint _amount, uint _totalBetAmount, uint8 _whoWIn, address _addr);
    event withDrawEvent(uint _gameId, address admin, uint _withDrawAmount, uint _balance);
    event ownerWithdrawEvent(address _owner ,uint _amount, uint _balance);
    event contractReceiveEvent(uint _value, uint _balance);
    
    //只能合约拥有者调用
    modifier onlyOwner {
       require( msg.sender == owner, "not owner" );
       _;
    }
    //只能管理员调用
    modifier onlyAdmin {
        uint i;
        address admin;
        for ( i=0; i<admins.length; i++ ){
            admin = admins[i];
            if (admin == msg.sender){
                break;
            }
        }
        require( admin == msg.sender, "not admin" );
        _;
    }
    
    //构造函数
    constructor(address _owner) public {
        require(_owner != address(0x0), "error: owner cannot to be 0x0");
        owner = _owner;
        addAdmin(_owner);           
    }
    
    //创建比赛
    function createGame(uint _id, string _hostTeam, string _guestTeam, int8 _point, uint _createTime, uint _stopBetTime) public onlyAdmin {
        require( gameActive, "contract is not active" );
        require(_point >= 50 || _point <= -50, "rqPoint must be 100 mul");  //  让球传入时扩大100倍
        
        gameMapping[_id] = SoccerGame(
            {
                status : GameStatus.original,       //初始状态
                
                gameInfo : GameInfo({
                    hostTeam : _hostTeam,
                    guestTeam : _guestTeam,
                    createTime : _createTime,
                    stopBetTime : _stopBetTime,
                    point : _point              //传入时为实际100倍，兼容小数
                }),
                
                gameScore : GameScore({
                    hostScore : 100,
                    guestScore : 100 
                }),
                  
                result : GameResult.original,
                
                betInfo : BetInfo({
                    betPlayerCount : 0,
                    betHostWinAmout : 0,
                    betGuestWinAmout : 0,
                    betEqualAmout : 0,
                    totalBetAmount : 0
                }),
                
                whoCreated : msg.sender,
                whoSetScore : 0x0,
                whoWithDraw : 0x0
            });
    
        emit createGameEvent(_id, msg.sender, _hostTeam, _guestTeam, _point, _stopBetTime);
    }
    
    //打开投注
    function openBet(uint _id) onlyAdmin public {
        require(GameStatus.original == gameMapping[_id].status, "game is not original status");
        gameMapping[_id].status = GameStatus.open;
        unWithdrawGameId.push(_id); //  加入为未派奖列表
        
        emit openGameEvent(_id, msg.sender);
    }
    
    //下注
    function bet(uint _id, uint8 _whoWin, uint _betTime) public payable{
        require( gameMapping[_id].status == GameStatus.open, "bet not open" );
        require( _betTime < gameMapping[_id].gameInfo.stopBetTime, "time's up" );
        require( uint8(GameResult.original) < _whoWin &&_whoWin <= uint8(GameResult.guestTeamWin), "whoWin error" );
        require( msg.value >= minimalBet, "less than minimalBet"); 
        require( msg.value <  maxBet, "beyond max amount" );
        require( msg.value+gameMapping[_id].betInfo.totalBetAmount <= totalBetLimit, "touch singl game bet limit" );
        
        BetPlayer memory player = BetPlayer( {addr : msg.sender, amount : msg.value, betStatus : GameResult.original, draw : false} );
        SoccerGame game = gameMapping[_id];
        
        if (_whoWin == uint8(GameResult.hostTeamWin)){
            player.betStatus = GameResult.hostTeamWin;
            game.betInfo.betHostWinAmout += player.amount;
        }
        else if (_whoWin == uint8(GameResult.guestTeamWin)){
            player.betStatus = GameResult.guestTeamWin;
            game.betInfo.betGuestWinAmout += player.amount;
        }
        else if (_whoWin == uint8(GameResult.equal)){
            player.betStatus = GameResult.equal;
            game.betInfo.betEqualAmout += player.amount;
        }
        
        game.betPlayerMapping[game.betInfo.betPlayerCount++] = player;
        //总投注金额
        game.betInfo.totalBetAmount += player.amount;
        
        emit playerBetEvent(_id, player.amount, game.betInfo.totalBetAmount, _whoWin, msg.sender);
    }
    
    //比赛开始前终止投注
    function stopBet(uint _id) public onlyAdmin{
        require(gameMapping[ _id].status == GameStatus.open, "game is not open status");
        gameMapping[_id].status = GameStatus.close;
        emit stopBetEvent(_id, msg.sender);
    }
    
    //设置比分
    function setScore(uint _id, uint8 _hostScore, uint8 _guestScore) onlyAdmin public {
        require(GameStatus.open != gameMapping[_id].status, "bet is going");
        gameMapping[_id].gameScore.hostScore = _hostScore;
        gameMapping[_id].gameScore.guestScore = _guestScore;
        
        gameMapping[_id].result = rqGameResult(_hostScore, _guestScore, gameMapping[_id].gameInfo.point);
        
        if (GameStatus.close == gameMapping[_id].status){   // 防止重复设置比分
            gameMapping[_id].status = GameStatus.setScore;
            gameMapping[_id].whoSetScore = msg.sender;
        }
    }
    
    //让球后比赛输赢结果
    function rqGameResult(uint8 _hostScore, uint8 _guestScore, int8 _rqPoint) onlyAdmin internal returns (GameResult) {
        require( _hostScore < 100 && _guestScore < 100, "score error" );
        uint8 hostScore = _hostScore * 100; //  配合让球小数情况扩大100倍
        uint8 guestScore = _guestScore * 100;
        if (_rqPoint < 0){  //约定负数为主队让球
            guestScore += uint8(-_rqPoint);
        }
        else if (_rqPoint > 0){ //约定正数为客队客队让球
            hostScore += uint8(_rqPoint);
        }
        
        if (hostScore > guestScore){    //  让球后主队主队胜
            return GameResult.hostTeamWin;
        }
        else if (hostScore < guestScore){   //  让球后客队胜
            return GameResult.guestTeamWin;
        }
        else{
            return GameResult.equal;    //平局
        }
    }
    
    //派奖提币
    function allPlayerWithDraw() payable onlyAdmin public returns(uint) {
        require(address(this).balance > 0, "balance is empty");
        require(unWithdrawGameId.length > 0, "all game was withdrawed");
        
        //uint gameId;
        SoccerGame game;
        BetPlayer player;
        GameResult result = GameResult.original;
        for (uint i=0; i<unWithdrawGameId.length; i++){
            //gameId = unWithdrawGameId[i];
            game = gameMapping[unWithdrawGameId[i]];
            if (game.betInfo.betPlayerCount == 0){  //  比赛下注人数为0
                continue;
            }
            
            result = game.result;
            
            uint totalBetHostWinAmount = game.betInfo.betHostWinAmout;
            uint totalBetGuestWinAmount = game.betInfo.betGuestWinAmout;
            uint totalBetEqualAmount = game.betInfo.betEqualAmout;
            
            uint rewardAmount = 0;          //待分配奖金，赢家通吃
            uint totalWinnerBetAmount = 0;  //赢家投注总金额
            uint playerReward = 0;          //玩家奖金
            
            if (result == GameResult.hostTeamWin){  //主队胜
                rewardAmount = (100-commission) * (totalBetEqualAmount + totalBetGuestWinAmount) / 100;
                totalWinnerBetAmount = totalBetHostWinAmount;
            }
            else if (result == GameResult.guestTeamWin){    //客队胜
                rewardAmount = (100-commission) * (totalBetEqualAmount + totalBetHostWinAmount) / 100;
                totalWinnerBetAmount = totalBetGuestWinAmount;
            }
            else if (result == GameResult.equal){   //平局
                rewardAmount = (100-commission) * (totalBetGuestWinAmount + totalBetHostWinAmount) / 100;
                totalWinnerBetAmount = totalBetEqualAmount;
            }
            
            for (uint j=0; j<game.betInfo.betPlayerCount; j++){
                player = game.betPlayerMapping[j];
                if (player.betStatus == result && player.draw == false){    //获胜并且未分配奖金
                    
                    playerReward = (player.amount*1000000/totalWinnerBetAmount * rewardAmount )/1000000 + player.amount;
                    player.addr.transfer(playerReward);
                    player.draw = true;
                }
            }
            
            emit withDrawEvent(unWithdrawGameId[i], msg.sender, rewardAmount+totalWinnerBetAmount , address(this).balance);
        }
        
        //派奖结束
        game.whoWithDraw = msg.sender;
        delete unWithdrawGameId;
        return address(this).balance;
    }
    
    //合约所有者提取收益
    function ownerWithDraw(uint _amount) payable onlyOwner public{
        require(unWithdrawGameId.length == 0, "has unwithdrawed games");   //未全部派奖不允许提取收益，避免误提用户奖金
        require(address(this).balance > _amount, "amount is not enough");
        owner.transfer(_amount);
        emit ownerWithdrawEvent(msg.sender, _amount, address(this).balance);
    }
    
    //改变合约所有者
    function changeOwner(address _owner) onlyOwner public {
        require(_owner != address(0x0), "error: owner address is 0x00");
        require(_owner != owner, "error: no changes");
        delAdmin(owner);
        owner = _owner;
        admins.push(_owner);
    }
    
    //添加管理员
    function addAdmin(address _admin) onlyOwner public {
        require(_admin != address(0x0), "error: admin address is 0x00");
        for (uint i=0; i<admins.length; i++){
            require(_admin != admins[i], "has this admin already");
        }
        admins.push(_admin);
    }
    
    //删除管理员
    function delAdmin(address _admin) onlyOwner public {
        require(admins.length > 1, "only one admin");
        require(_admin != owner, "error: cannot delete owner");
        for (uint i=0; i<admins.length; ++i){
            if (_admin == admins[i]){
                //前移一位
                for (uint j=i; j<admins.length-1; ++j){
                    admins[j] = admins[j+1];
                }
                delete admins[admins.length-1];
                admins.length--;
                break;
            }
        }
    }
    
    //修改分成比例
    function changeCommissionRate(uint8 _rate) onlyOwner public {
        require(_rate >= 0 && _rate <= 10, "rate error");       //分成在0到10个百分点之间
        require(_rate != commission, "error: no changes");
        commission = _rate;
    }
    
    //修改合约状态
    function changeContractActive(bool _active) onlyOwner public {
        require(_active != gameActive, "error: no changes");
        gameActive = _active;
    }
    
    //回调函数
    function () external payable{
        emit contractReceiveEvent(msg.value, address(this).balance);
    }
    
}
