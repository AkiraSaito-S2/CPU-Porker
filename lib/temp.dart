import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const PokerApp());
}

class PokerApp extends StatelessWidget {
  const PokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Texas Hold\'em AI',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF35654d), // Poker table green
        useMaterial3: true,
      ),
      home: const PokerTablePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Models (データモデル)
// ---------------------------------------------------------------------------

enum Suit { spade, heart, diamond, club }
enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }
enum GamePhase { preFlop, flop, turn, river, showDown }

// 役の強さ定義（強い順）
enum HandRank {
  highCard,
  onePair,
  twoPair,
  threeOfAKind,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
  royalFlush
}

class CardModel {
  final Suit suit;
  final Rank rank;

  const CardModel(this.suit, this.rank);

  @override
  String toString() => '${rank.name} of ${suit.name}';

  int get value => Rank.values.indexOf(rank) + 2;

  String get displayRank {
    switch (rank) {
      case Rank.ace: return 'A';
      case Rank.king: return 'K';
      case Rank.queen: return 'Q';
      case Rank.jack: return 'J';
      case Rank.ten: return '10';
      default: return value.toString();
    }
  }

  Color get color => (suit == Suit.heart || suit == Suit.diamond) ? Colors.red : Colors.black;
  
  String get suitSymbol {
    switch (suit) {
      case Suit.spade: return '♠';
      case Suit.heart: return '♥';
      case Suit.diamond: return '♦';
      case Suit.club: return '♣';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardModel &&
          runtimeType == other.runtimeType &&
          suit == other.suit &&
          rank == other.rank;

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;
}

class Deck {
  List<CardModel> cards = [];

  Deck() {
    _initialize();
  }

  void _initialize() {
    cards.clear();
    for (var suit in Suit.values) {
      for (var rank in Rank.values) {
        cards.add(CardModel(suit, rank));
      }
    }
    shuffle();
  }

  void shuffle() {
    cards.shuffle(Random());
  }

  CardModel draw() {
    if (cards.isEmpty) _initialize();
    return cards.removeLast();
  }
  
  static List<CardModel> getRemainingCards(List<CardModel> excluded) {
    List<CardModel> fullDeck = [];
    for (var suit in Suit.values) {
      for (var rank in Rank.values) {
        fullDeck.add(CardModel(suit, rank));
      }
    }
    for (var ex in excluded) {
      fullDeck.removeWhere((c) => c == ex);
    }
    return fullDeck;
  }
}

// ---------------------------------------------------------------------------
// Hand Evaluator (役判定ロジック)
// ---------------------------------------------------------------------------

class HandStrength implements Comparable<HandStrength> {
  final HandRank rank;
  final List<int> kickers;

  HandStrength(this.rank, this.kickers);

  @override
  int compareTo(HandStrength other) {
    if (rank.index != other.rank.index) {
      return rank.index.compareTo(other.rank.index);
    }
    for (int i = 0; i < kickers.length; i++) {
      if (i >= other.kickers.length) return 1;
      if (kickers[i] != other.kickers[i]) {
        return kickers[i].compareTo(other.kickers[i]);
      }
    }
    return 0;
  }

  @override
  String toString() {
    String rankName = rank.name;
    return rankName[0].toUpperCase() + rankName.substring(1);
  }
}

class PokerEvaluator {
  static HandStrength evaluate(List<CardModel> sevenCards) {
    List<List<CardModel>> combinations = _getCombinations(sevenCards, 5);
    HandStrength bestHand = HandStrength(HandRank.highCard, []);
    for (var hand in combinations) {
      HandStrength strength = _evaluateFiveCards(hand);
      if (strength.compareTo(bestHand) > 0) {
        bestHand = strength;
      }
    }
    return bestHand;
  }

  static List<List<CardModel>> _getCombinations(List<CardModel> source, int k) {
    List<List<CardModel>> result = [];
    void backtrack(int start, List<CardModel> current) {
      if (current.length == k) {
        result.add(List.from(current));
        return;
      }
      for (int i = start; i < source.length; i++) {
        current.add(source[i]);
        backtrack(i + 1, current);
        current.removeLast();
      }
    }
    backtrack(0, []);
    return result;
  }

  static HandStrength _evaluateFiveCards(List<CardModel> hand) {
    hand.sort((a, b) => b.value.compareTo(a.value));
    
    bool isFlush = _isFlush(hand);
    bool isStraight = _isStraight(hand);

    if (isFlush && isStraight) {
      if (hand.first.value == 14 && hand.last.value == 10) {
        return HandStrength(HandRank.royalFlush, []);
      }
      return HandStrength(HandRank.straightFlush, [hand.first.value]);
    }

    Map<int, int> counts = {};
    for (var card in hand) {
      counts[card.value] = (counts[card.value] ?? 0) + 1;
    }
    
    List<int> fours = [];
    List<int> threes = [];
    List<int> pairs = [];
    List<int> singles = [];

    counts.forEach((val, count) {
      if (count == 4) fours.add(val);
      else if (count == 3) threes.add(val);
      else if (count == 2) pairs.add(val);
      else singles.add(val);
    });

    fours.sort((a, b) => b.compareTo(a));
    threes.sort((a, b) => b.compareTo(a));
    pairs.sort((a, b) => b.compareTo(a));
    singles.sort((a, b) => b.compareTo(a));

    if (fours.isNotEmpty) {
      return HandStrength(HandRank.fourOfAKind, [fours[0], ...singles]);
    }
    if (threes.isNotEmpty && pairs.isNotEmpty) {
      return HandStrength(HandRank.fullHouse, [threes[0], pairs[0]]);
    }
    if (isFlush) {
      return HandStrength(HandRank.flush, hand.map((c) => c.value).toList());
    }
    if (isStraight) {
      return HandStrength(HandRank.straight, [hand.first.value]);
    }
    if (threes.isNotEmpty) {
      return HandStrength(HandRank.threeOfAKind, [threes[0], ...singles]);
    }
    if (pairs.length >= 2) {
      return HandStrength(HandRank.twoPair, [pairs[0], pairs[1], ...singles]);
    }
    if (pairs.length == 1) {
      return HandStrength(HandRank.onePair, [pairs[0], ...singles]);
    }

    return HandStrength(HandRank.highCard, hand.map((c) => c.value).toList());
  }

  static bool _isFlush(List<CardModel> hand) {
    Suit firstSuit = hand[0].suit;
    return hand.every((c) => c.suit == firstSuit);
  }

  static bool _isStraight(List<CardModel> hand) {
    if (hand[0].rank == Rank.ace && 
        hand[1].rank == Rank.five && 
        hand[4].rank == Rank.two) {
      return true;
    }
    for (int i = 0; i < hand.length - 1; i++) {
      if (hand[i].value - hand[i+1].value != 1) {
        return false;
      }
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Monte Carlo AI (AIロジック)
// ---------------------------------------------------------------------------

class MonteCarloAI {
  static const int SIMULATION_COUNT = 600;

  static Future<Map<String, dynamic>> decideAction(
      List<CardModel> cpuHand, List<CardModel> communityCards) async {
    
    return await Future.delayed(const Duration(milliseconds: 100), () {
      double winRate = _calculateWinRate(cpuHand, communityCards);
      String action;
      
      // 勝率に基づくアクション決定
      if (winRate > 0.75) {
        action = 'Raise';
      } else if (winRate > 0.40) {
        action = 'Call';
      } else {
        // 勝率が低くてもCallがタダ(Check)ならCallを返す等の判断はEngine側で行うため
        // ここでは純粋な意志としてFoldを返すが、Engine側で補正する
        action = 'Fold';
      }
      return {'action': action, 'winRate': winRate};
    });
  }

  static double _calculateWinRate(List<CardModel> cpuHand, List<CardModel> communityCards) {
    int wins = 0;
    int ties = 0;
    int total = SIMULATION_COUNT;
    List<CardModel> knownCards = [...cpuHand, ...communityCards];
    List<CardModel> deck = Deck.getRemainingCards(knownCards);
    int neededCommunity = 5 - communityCards.length;

    for (int i = 0; i < total; i++) {
      deck.shuffle();
      int deckIndex = 0;
      List<CardModel> simCommunity = List.from(communityCards);
      for (int j = 0; j < neededCommunity; j++) {
        simCommunity.add(deck[deckIndex++]);
      }
      List<CardModel> opponentHand = [deck[deckIndex++], deck[deckIndex++]];
      
      HandStrength cpuStrength = PokerEvaluator.evaluate([...cpuHand, ...simCommunity]);
      HandStrength oppStrength = PokerEvaluator.evaluate([...opponentHand, ...simCommunity]);

      int result = cpuStrength.compareTo(oppStrength);
      if (result > 0) wins++;
      else if (result == 0) ties++;
    }
    return (wins + (ties * 0.5)) / total;
  }
}

// ---------------------------------------------------------------------------
// Game Engine (ゲーム進行・ベッティング管理)
// ---------------------------------------------------------------------------

class PokerGameEngine extends ChangeNotifier {
  Deck _deck = Deck();
  List<CardModel> playerHand = [];
  List<CardModel> cpuHand = [];
  List<CardModel> communityCards = [];
  
  GamePhase _phase = GamePhase.preFlop;
  String message = "ゲーム開始待機中";
  String cpuThought = "";
  
  // ベッティング関連の状態
  int pot = 0;
  int playerStack = 1000;
  int cpuStack = 1000;
  
  // 現在のストリート（ラウンド）でのベット額
  int playerStreetBet = 0;
  int cpuStreetBet = 0;
  
  // 最小ベット額 / ブラインド
  static const int smallBlind = 10;
  static const int bigBlind = 20;

  // ターン管理
  bool isPlayerTurn = false;
  bool isPlayerButton = true; // ディーラーボタンの位置（1vs1ではButton=SB）
  
  // アクション完了フラグ（両者が同意して次のラウンドへ行けるか）
  bool _playerActed = false;
  bool _cpuActed = false;

  GamePhase get phase => _phase;

  // アクション可能かどうか（例：相手がRaiseしたのにCheckはできない）
  bool get canCheck => playerStreetBet == cpuStreetBet;

  void startNewGame() {
    _deck = Deck();
    playerHand = [_deck.draw(), _deck.draw()];
    cpuHand = [_deck.draw(), _deck.draw()];
    communityCards = [];
    _phase = GamePhase.preFlop;
    cpuThought = "";
    
    // チップリセット（破産していたら補充）
    if (playerStack < bigBlind || cpuStack < bigBlind) {
      playerStack = 1000;
      cpuStack = 1000;
      message = "チップを補充しました！";
    }

    // ブラインド支払い & ボタン移動
    isPlayerButton = !isPlayerButton; // ボタンを交代
    pot = 0;
    playerStreetBet = 0;
    cpuStreetBet = 0;
    _playerActed = false;
    _cpuActed = false;

    // 1vs1ルール: ButtonがSBを払う。Buttonじゃない方がBBを払う。
    // PreFlop: Button(SB)が先に行動。
    // PostFlop: 非Button(BB)が先に行動。

    if (isPlayerButton) {
      // プレイヤーがSB(Button)
      _betPlayer(smallBlind);
      _betCpu(bigBlind);
      isPlayerTurn = true; // SB(Player)からアクション
      message = "あなたは Dealer(SB) です。アクションを選択してください。";
    } else {
      // CPUがSB(Button)
      _betCpu(smallBlind);
      _betPlayer(bigBlind);
      isPlayerTurn = false; // SB(CPU)からアクション
      message = "あなたは BB です。CPU(SB)のアクション待ち...";
      Future.delayed(const Duration(seconds: 1), _cpuTurn);
    }
    
    notifyListeners();
  }

  void _betPlayer(int amount) {
    if (playerStack < amount) amount = playerStack; // All-in
    playerStack -= amount;
    playerStreetBet += amount;
    pot += amount;
  }

  void _betCpu(int amount) {
    if (cpuStack < amount) amount = cpuStack; // All-in
    cpuStack -= amount;
    cpuStreetBet += amount;
    pot += amount;
  }

  void playerAction(String actionType) {
    if (!isPlayerTurn) return;

    int callAmount = cpuStreetBet - playerStreetBet;

    if (actionType == "Fold") {
      message = "プレイヤー Fold。CPUの勝ち！";
      _givePotToWinner(isPlayer: false);
      return;
    } else if (actionType == "Check") {
      if (!canCheck) return; // Checkできない状況でのCheckは無視
      message = "プレイヤー: Check";
    } else if (actionType == "Call") {
      _betPlayer(callAmount);
      message = "プレイヤー: Call ($callAmount)";
    } else if (actionType == "Raise") {
      // 簡易実装: レイズ額は「現在のベット差額 + ポットの50%」程度とする
      int raiseAmount = callAmount + (pot ~/ 2);
      if (raiseAmount < bigBlind) raiseAmount = bigBlind; // ミニマムレイズ
      _betPlayer(raiseAmount);
      message = "プレイヤー: Raise ($raiseAmount)";
      // レイズされたのでCPUのアクションフラグをリセット（再度意思決定が必要）
      _cpuActed = false;
    }

    _playerActed = true;
    isPlayerTurn = false;
    notifyListeners();
    
    _checkNextPhaseOrTurn();
  }

  Future<void> _cpuTurn() async {
    if (_phase == GamePhase.showDown) return;

    message = "CPU: 思考中...";
    notifyListeners();

    final aiResult = await MonteCarloAI.decideAction(cpuHand, communityCards);
    String action = aiResult['action'];
    double winRate = aiResult['winRate'];

    int callAmount = playerStreetBet - cpuStreetBet;
    
    // --- AIのアクション補正 ---
    // Checkできる状況でFoldはしない
    if (action == 'Fold' && callAmount == 0) {
      action = 'Check';
    }
    // Call額が高すぎる場合のFold判断（簡易オッズ）
    // 勝率40%以下で、Call額がスタックの20%を超えるなら降りる
    if (action == 'Call' && winRate < 0.4 && callAmount > cpuStack * 0.2) {
      action = 'Fold';
    }
    // ------------------------

    if (action == "Fold") {
      cpuThought = "勝率: ${(winRate * 100).toStringAsFixed(1)}% -> Fold";
      message = "CPU Fold。あなたの勝ち！";
      _givePotToWinner(isPlayer: true);
      notifyListeners();
      return;
    } else if (action == "Check") {
       // CheckできないならCallに変更
       if (callAmount > 0) action = "Call";
    }

    // 最終実行
    if (action == "Check" || (action == "Call" && callAmount == 0)) {
      action = "Check";
      message = "CPU: Check";
    } else if (action == "Call") {
      _betCpu(callAmount);
      message = "CPU: Call";
    } else if (action == "Raise") {
      // 勝率に応じてレイズ額を変える
      int added = (winRate > 0.8) ? pot : (pot ~/ 2); // 強いとポットベット、普通ならハーフポット
      int raiseAmount = callAmount + added;
      _betCpu(raiseAmount);
      message = "CPU: Raise";
      // レイズされたのでプレイヤーのアクションフラグをリセット
      _playerActed = false;
    }

    cpuThought = "勝率: ${(winRate * 100).toStringAsFixed(1)}% -> $action";
    _cpuActed = true;
    isPlayerTurn = true;
    notifyListeners();

    _checkNextPhaseOrTurn();
  }

  void _checkNextPhaseOrTurn() {
    // 両者がアクション済み かつ ベット額が同じ（またはAll-in）なら次フェーズへ
    bool amountsEqual = playerStreetBet == cpuStreetBet;
    // どちらかがAll-inしている場合も進む
    bool isAllIn = playerStack == 0 || cpuStack == 0;

    if ((_playerActed && _cpuActed && amountsEqual) || (_playerActed && _cpuActed && isAllIn)) {
      Future.delayed(const Duration(milliseconds: 800), _nextPhase);
    } else {
      // まだラウンドが続く場合、手番を回す
      if (isPlayerTurn) {
        message = "あなたのアクションです";
      } else {
        Future.delayed(const Duration(milliseconds: 800), _cpuTurn);
      }
      notifyListeners();
    }
  }

  void _nextPhase() {
    // ベット額リセット
    playerStreetBet = 0;
    cpuStreetBet = 0;
    _playerActed = false;
    _cpuActed = false;

    switch (_phase) {
      case GamePhase.preFlop:
        _phase = GamePhase.flop;
        communityCards.addAll([_deck.draw(), _deck.draw(), _deck.draw()]);
        message = "Flopが開かれました";
        break;
      case GamePhase.flop:
        _phase = GamePhase.turn;
        communityCards.add(_deck.draw());
        message = "Turnが開かれました";
        break;
      case GamePhase.turn:
        _phase = GamePhase.river;
        communityCards.add(_deck.draw());
        message = "Riverが開かれました";
        break;
      case GamePhase.river:
        _showDown();
        return;
      case GamePhase.showDown:
        return;
    }
    
    // PostFlopのアクション順序: Buttonでない方(BB)から
    // isPlayerButton == true (Player=SB) なら、CPU(BB)が先
    if (isPlayerButton) {
      isPlayerTurn = false;
      Future.delayed(const Duration(milliseconds: 1000), _cpuTurn);
    } else {
      isPlayerTurn = true;
      message = "あなたのアクション番です";
    }
    notifyListeners();
  }

  void _givePotToWinner({required bool isPlayer}) {
    _phase = GamePhase.showDown;
    if (isPlayer) {
      playerStack += pot;
    } else {
      cpuStack += pot;
    }
    pot = 0;
    notifyListeners();
  }

  void _showDown() {
    _phase = GamePhase.showDown;
    
    final playerResult = PokerEvaluator.evaluate([...playerHand, ...communityCards]);
    final cpuResult = PokerEvaluator.evaluate([...cpuHand, ...communityCards]);

    int comparison = playerResult.compareTo(cpuResult);
    String resultText;
    
    if (comparison > 0) {
      resultText = "あなたの勝ち！ (+${pot})";
      playerStack += pot;
    } else if (comparison < 0) {
      resultText = "CPUの勝ち... (-${pot})";
      cpuStack += pot;
    } else {
      resultText = "引き分け！ (Split)";
      playerStack += pot ~/ 2;
      cpuStack += pot ~/ 2;
    }
    pot = 0; // 配り終えたので0にする

    message = "$resultText\nYou:${playerResult.toString()} vs CPU:${cpuResult.toString()}";
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// UI Widgets (画面表示)
// ---------------------------------------------------------------------------

class PokerTablePage extends StatefulWidget {
  const PokerTablePage({super.key});

  @override
  State<PokerTablePage> createState() => _PokerTablePageState();
}

class _PokerTablePageState extends State<PokerTablePage> {
  final PokerGameEngine _game = PokerGameEngine();

  @override
  void initState() {
    super.initState();
    _game.addListener(() {
      setState(() {});
    });
    // 初期化はビルド後に
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 最初のゲームは手動スタート待ちにするならここはコメントアウト
       _game.startNewGame();
    });
  }

  @override
  Widget build(BuildContext context) {
    bool canCheck = _game.canCheck;
    int toCall = _game.cpuStreetBet - _game.playerStreetBet;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Texas Hold\'em AI'),
        backgroundColor: Colors.black26,
        actions: [
           IconButton(icon: const Icon(Icons.refresh), onPressed: () => _game.startNewGame()),
        ],
      ),
      body: Column(
        children: [
          // --- CPU Area ---
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StackInfoWidget(name: "CPU", stack: _game.cpuStack, isDealer: !_game.isPlayerButton),
                  const SizedBox(height: 8),
                  if (_game.cpuThought.isNotEmpty && _game.phase != GamePhase.showDown)
                    Text(_game.cpuThought, style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _game.phase == GamePhase.showDown
                        ? _game.cpuHand.map((c) => CardWidget(card: c)).toList()
                        : [const CardBackWidget(), const SizedBox(width: 8), const CardBackWidget()],
                  ),
                  if (_game.cpuStreetBet > 0)
                     ChipPilesWidget(amount: _game.cpuStreetBet),
                ],
              ),
            ),
          ),

          // --- Table Area ---
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Pot: \$${_game.pot}", style: const TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 90,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _game.communityCards.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CardWidget(card: c),
                    )).toList(),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                  child: Text(_game.message, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
          ),

          // --- Player Area ---
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black26,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_game.playerStreetBet > 0)
                     ChipPilesWidget(amount: _game.playerStreetBet),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _game.playerHand.map((c) => CardWidget(card: c)).toList(),
                  ),
                  const SizedBox(height: 8),
                  StackInfoWidget(name: "YOU", stack: _game.playerStack, isDealer: _game.isPlayerButton),
                  const SizedBox(height: 16),
                  
                  // Action Buttons
                  if (_game.phase == GamePhase.showDown)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Next Hand"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      onPressed: _game.startNewGame, 
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ActionButton(
                          label: "Fold", 
                          color: Colors.red[900]!, 
                          onPressed: () => _game.playerAction("Fold")
                        ),
                        ActionButton(
                          label: canCheck ? "Check" : "Call \$$toCall", 
                          color: Colors.blue[800]!, 
                          onPressed: () => _game.playerAction(canCheck ? "Check" : "Call")
                        ),
                        ActionButton(
                          label: "Raise", 
                          color: Colors.orange[800]!, 
                          onPressed: () => _game.playerAction("Raise")
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// UI Components
class StackInfoWidget extends StatelessWidget {
  final String name;
  final int stack;
  final bool isDealer;

  const StackInfoWidget({super.key, required this.name, required this.stack, required this.isDealer});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDealer) 
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Text("D", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        const SizedBox(width: 8),
        Column(
          children: [
            Text(name, style: const TextStyle(color: Colors.white70)),
            Text("\$$stack", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

class ChipPilesWidget extends StatelessWidget {
  final int amount;
  const ChipPilesWidget({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.yellow[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white38)
      ),
      child: Text("\$$amount", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
    );
  }
}

class CardWidget extends StatelessWidget {
  final CardModel card;
  const CardWidget({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 75,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(1, 1), blurRadius: 2)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(card.displayRank, style: TextStyle(color: card.color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(card.suitSymbol, style: TextStyle(color: card.color, fontSize: 20)),
        ],
      ),
    );
  }
}

class CardBackWidget extends StatelessWidget {
  const CardBackWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 75,
      decoration: BoxDecoration(
        color: Colors.blue[900],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Center(child: Icon(Icons.pattern, color: Colors.white24, size: 20)),
    );
  }
}

class ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const ActionButton({super.key, required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}