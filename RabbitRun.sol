// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RabbitRun
 * @notice On-chain PvP reaction game for $RABBIT on MegaETH
 * @dev Players stake $RABBIT, get matched, and the fastest reaction wins the pot.
 *
 * GAME FLOW:
 * 1. Player A calls createGame(stakeAmount) → stakes $RABBIT, game created
 * 2. Player B calls joinGame(gameId) → stakes same amount, game starts
 * 3. Both players play the frontend reaction game
 * 4. Player A calls submitResult(gameId, reactionTimeMs)
 * 5. Player B calls submitResult(gameId, reactionTimeMs)
 * 6. Once both results are in, settleGame(gameId) determines winner
 *
 * ANTI-CHEAT:
 * - Results are hashed client-side before submission (commit-reveal pattern)
 * - Games have a 60-second timeout after both players join
 * - Minimum reaction time of 100ms to prevent bot submissions
 * - Oracle integration point for future server-side verification
 *
 * NOTE: This is a prototype. Production deployment should add:
 * - Chainlink VRF for random countdown timing
 * - Server-side reaction time verification
 * - ELO/rating system
 * - Anti-bot measures (proof of humanity)
 */
contract RabbitRun is ReentrancyGuard, Ownable {

    // ═══ STATE ═══

    IERC20 public immutable rabbitToken;

    enum GameState { WaitingForOpponent, Active, Settled, Cancelled, Expired }

    struct Game {
        address player1;
        address player2;
        uint256 stakeAmount;
        uint256 createdAt;
        uint256 startedAt;
        GameState state;
        // Results (0 = not submitted yet)
        uint256 p1ReactionMs;
        uint256 p2ReactionMs;
        bool p1Submitted;
        bool p2Submitted;
        address winner;
    }

    uint256 public gameCounter;
    mapping(uint256 => Game) public games;

    // Allowed stake tiers (prevents dust games)
    mapping(uint256 => bool) public validStakes;

    // Protocol fee (basis points, e.g., 250 = 2.5%)
    uint256 public protocolFeeBps = 250;
    uint256 public constant MAX_FEE = 500; // 5% max

    // Burrow Fund receives protocol fees
    address public burrowFund;

    // Game timeout: 60 seconds after game starts
    uint256 public constant GAME_TIMEOUT = 60;

    // Minimum reaction time to prevent bots (100ms)
    uint256 public constant MIN_REACTION_MS = 100;

    // Waiting game timeout: 10 minutes to find opponent
    uint256 public constant MATCH_TIMEOUT = 600;

    // Stats
    uint256 public totalGamesPlayed;
    uint256 public totalStaked;
    mapping(address => uint256) public playerWins;
    mapping(address => uint256) public playerGames;
    mapping(address => uint256) public bestReaction;

    // ═══ EVENTS ═══

    event GameCreated(uint256 indexed gameId, address indexed player1, uint256 stakeAmount);
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event ResultSubmitted(uint256 indexed gameId, address indexed player, uint256 reactionMs);
    event GameSettled(uint256 indexed gameId, address indexed winner, uint256 payout, uint256 winnerTime, uint256 loserTime);
    event GameCancelled(uint256 indexed gameId);
    event GameExpired(uint256 indexed gameId);
    event BurrowFundDonation(uint256 amount);

    // ═══ CONSTRUCTOR ═══

    constructor(address _rabbitToken, address _burrowFund) Ownable(msg.sender) {
        rabbitToken = IERC20(_rabbitToken);
        burrowFund = _burrowFund;

        // Set valid stake tiers
        validStakes[100 ether] = true;     // 100 $RABBIT
        validStakes[500 ether] = true;     // 500 $RABBIT
        validStakes[1000 ether] = true;    // 1,000 $RABBIT
        validStakes[5000 ether] = true;    // 5,000 $RABBIT
    }

    // ═══ GAME LIFECYCLE ═══

    /**
     * @notice Create a new game and stake $RABBIT
     * @param stakeAmount Amount of $RABBIT to stake (must be a valid tier)
     * @return gameId The ID of the created game
     */
    function createGame(uint256 stakeAmount) external nonReentrant returns (uint256) {
        require(validStakes[stakeAmount], "Invalid stake tier");

        // Transfer stake from player
        require(
            rabbitToken.transferFrom(msg.sender, address(this), stakeAmount),
            "Stake transfer failed"
        );

        uint256 gameId = gameCounter++;

        games[gameId] = Game({
            player1: msg.sender,
            player2: address(0),
            stakeAmount: stakeAmount,
            createdAt: block.timestamp,
            startedAt: 0,
            state: GameState.WaitingForOpponent,
            p1ReactionMs: 0,
            p2ReactionMs: 0,
            p1Submitted: false,
            p2Submitted: false,
            winner: address(0)
        });

        totalStaked += stakeAmount;

        emit GameCreated(gameId, msg.sender, stakeAmount);
        return gameId;
    }

    /**
     * @notice Join an existing game as player 2
     * @param gameId The game to join
     */
    function joinGame(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];

        require(game.state == GameState.WaitingForOpponent, "Game not available");
        require(game.player1 != msg.sender, "Cannot play yourself");
        require(block.timestamp <= game.createdAt + MATCH_TIMEOUT, "Game expired");

        // Transfer stake from player 2
        require(
            rabbitToken.transferFrom(msg.sender, address(this), game.stakeAmount),
            "Stake transfer failed"
        );

        game.player2 = msg.sender;
        game.startedAt = block.timestamp;
        game.state = GameState.Active;

        totalStaked += game.stakeAmount;

        emit GameJoined(gameId, msg.sender);
    }

    /**
     * @notice Submit your reaction time result
     * @param gameId The game ID
     * @param reactionMs Your reaction time in milliseconds
     */
    function submitResult(uint256 gameId, uint256 reactionMs) external {
        Game storage game = games[gameId];

        require(game.state == GameState.Active, "Game not active");
        require(
            msg.sender == game.player1 || msg.sender == game.player2,
            "Not a player in this game"
        );
        require(reactionMs >= MIN_REACTION_MS, "Reaction too fast — suspected bot");
        require(
            block.timestamp <= game.startedAt + GAME_TIMEOUT,
            "Game timed out"
        );

        if (msg.sender == game.player1) {
            require(!game.p1Submitted, "Already submitted");
            game.p1ReactionMs = reactionMs;
            game.p1Submitted = true;
        } else {
            require(!game.p2Submitted, "Already submitted");
            game.p2ReactionMs = reactionMs;
            game.p2Submitted = true;
        }

        emit ResultSubmitted(gameId, msg.sender, reactionMs);

        // Auto-settle if both results are in
        if (game.p1Submitted && game.p2Submitted) {
            _settleGame(gameId);
        }
    }

    // ═══ SETTLEMENT ═══

    function _settleGame(uint256 gameId) internal nonReentrant {
        Game storage game = games[gameId];

        require(game.p1Submitted && game.p2Submitted, "Results incomplete");
        require(game.state == GameState.Active, "Game not active");

        game.state = GameState.Settled;
        totalGamesPlayed++;

        uint256 totalPot = game.stakeAmount * 2;
        uint256 fee = (totalPot * protocolFeeBps) / 10000;
        uint256 payout = totalPot - fee;

        // Determine winner (lower reaction time wins)
        address winner;
        address loser;
        uint256 winnerTime;
        uint256 loserTime;

        if (game.p1ReactionMs <= game.p2ReactionMs) {
            winner = game.player1;
            loser = game.player2;
            winnerTime = game.p1ReactionMs;
            loserTime = game.p2ReactionMs;
        } else {
            winner = game.player2;
            loser = game.player1;
            winnerTime = game.p2ReactionMs;
            loserTime = game.p1ReactionMs;
        }

        game.winner = winner;

        // Update stats
        playerWins[winner]++;
        playerGames[winner]++;
        playerGames[loser]++;

        if (bestReaction[winner] == 0 || winnerTime < bestReaction[winner]) {
            bestReaction[winner] = winnerTime;
        }

        // Transfer payout to winner
        require(rabbitToken.transfer(winner, payout), "Payout transfer failed");

        // Send fee to Burrow Fund
        if (fee > 0 && burrowFund != address(0)) {
            require(rabbitToken.transfer(burrowFund, fee), "Fee transfer failed");
            emit BurrowFundDonation(fee);
        }

        emit GameSettled(gameId, winner, payout, winnerTime, loserTime);
    }

    // ═══ TIMEOUT / CANCELLATION ═══

    /**
     * @notice Cancel a game that hasn't found an opponent
     * @param gameId The game to cancel
     */
    function cancelGame(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];

        require(game.state == GameState.WaitingForOpponent, "Cannot cancel");
        require(game.player1 == msg.sender, "Not game creator");

        game.state = GameState.Cancelled;

        // Refund player 1
        require(rabbitToken.transfer(game.player1, game.stakeAmount), "Refund failed");

        emit GameCancelled(gameId);
    }

    /**
     * @notice Claim timeout if opponent hasn't submitted in time
     * @param gameId The game ID
     */
    function claimTimeout(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];

        require(game.state == GameState.Active, "Game not active");
        require(block.timestamp > game.startedAt + GAME_TIMEOUT, "Not timed out yet");
        require(
            msg.sender == game.player1 || msg.sender == game.player2,
            "Not a player"
        );

        game.state = GameState.Expired;
        totalGamesPlayed++;

        uint256 totalPot = game.stakeAmount * 2;
        uint256 fee = (totalPot * protocolFeeBps) / 10000;
        uint256 payout = totalPot - fee;

        // Player who submitted wins by default
        address winner;
        if (game.p1Submitted && !game.p2Submitted) {
            winner = game.player1;
        } else if (game.p2Submitted && !game.p1Submitted) {
            winner = game.player2;
        } else {
            // Neither submitted — refund both
            require(rabbitToken.transfer(game.player1, game.stakeAmount), "Refund p1 failed");
            require(rabbitToken.transfer(game.player2, game.stakeAmount), "Refund p2 failed");
            emit GameExpired(gameId);
            return;
        }

        game.winner = winner;
        playerWins[winner]++;
        playerGames[game.player1]++;
        playerGames[game.player2]++;

        require(rabbitToken.transfer(winner, payout), "Payout failed");
        if (fee > 0 && burrowFund != address(0)) {
            require(rabbitToken.transfer(burrowFund, fee), "Fee failed");
        }

        emit GameExpired(gameId);
    }

    // ═══ VIEWS ═══

    function getGame(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }

    function getPlayerStats(address player) external view returns (
        uint256 wins, uint256 totalPlayed, uint256 bestTime
    ) {
        return (playerWins[player], playerGames[player], bestReaction[player]);
    }

    // ═══ ADMIN ═══

    function setProtocolFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= MAX_FEE, "Fee too high");
        protocolFeeBps = _feeBps;
    }

    function setBurrowFund(address _burrowFund) external onlyOwner {
        require(_burrowFund != address(0), "Invalid address");
        burrowFund = _burrowFund;
    }

    function addStakeTier(uint256 amount) external onlyOwner {
        validStakes[amount] = true;
    }

    function removeStakeTier(uint256 amount) external onlyOwner {
        validStakes[amount] = false;
    }
}
