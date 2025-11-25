import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // システム音のために追加
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
        scaffoldBackgroundColor: const Color(0xFF35654d),
        useMaterial3: true,
        sliderTheme: const SliderThemeData(
          showValueIndicator: ShowValueIndicator.always,
        ),
      ),
      home: const PokerTablePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum Suit { spade, heart, diamond, club }
enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }
enum GamePhase { preFlop, flop, turn, river, showDown }

enum HandRank {
  highCard, onePair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush, royalFlush
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
      identical(this, other) || other is CardModel && runtimeType == other.runtimeType && suit == other.suit && rank == other.rank;
  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;
}

class Deck {
  List<CardModel> cards = [];
  Deck() { _initialize(); }
  void _initialize() {
    cards.clear();
    for (var suit in Suit.values) {
      for (var rank in Rank.values) cards.add(CardModel(suit, rank));
    }
    shuffle();
  }
  void shuffle() { cards.shuffle(Random()); }
  CardModel draw() {
    if (cards.isEmpty) _initialize();
    return cards.removeLast();
  }
  static List<CardModel> getRemainingCards(List<CardModel> excluded) {
    List<CardModel> fullDeck = [];
    for (var suit in Suit.values) {
      for (var rank in Rank.values) fullDeck.add(CardModel(suit, rank));
    }
    for (var ex in excluded) fullDeck.removeWhere((c) => c == ex);
    return fullDeck;
  }
}

// ---------------------------------------------------------------------------
// Evaluator & AI (Hand Range Estimation implemented)
// ---------------------------------------------------------------------------

class HandStrength implements Comparable<HandStrength> {
  final HandRank rank;
  final List<int> kickers;
  HandStrength(this.rank, this.kickers);
  @override
  int compareTo(HandStrength other) {
    if (rank.index != other.rank.index) return rank.index.compareTo(other.rank.index);
    for (int i = 0; i < kickers.length; i++) {
      if (i >= other.kickers.length) return 1;
      if (kickers[i] != other.kickers[i]) return kickers[i].compareTo(other.kickers[i]);
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
      if (strength.compareTo(bestHand) > 0) bestHand = strength;
    }
    return bestHand;
  }
  static List<List<CardModel>> _getCombinations(List<CardModel> source, int k) {
    List<List<CardModel>> result = [];
    void backtrack(int start, List<CardModel> current) {
      if (current.length == k) { result.add(List.from(current)); return; }
      for (int i = start; i < source.length; i++) {
        current.add(source[i]); backtrack(i + 1, current); current.removeLast();
      }
    }
    backtrack(0, []); return result;
  }
  static HandStrength _evaluateFiveCards(List<CardModel> hand) {
    hand.sort((a, b) => b.value.compareTo(a.value));
    bool isFlush = _isFlush(hand);
    bool isStraight = _isStraight(hand);
    if (isFlush && isStraight) {
      if (hand.first.value == 14 && hand.last.value == 10) return HandStrength(HandRank.royalFlush, []);
      return HandStrength(HandRank.straightFlush, [hand.first.value]);
    }
    Map<int, int> counts = {};
    for (var card in hand) counts[card.value] = (counts[card.value] ?? 0) + 1;
    List<int> fours = [], threes = [], pairs = [], singles = [];
    counts.forEach((val, count) {
      if (count == 4) fours.add(val); else if (count == 3) threes.add(val); else if (count == 2) pairs.add(val); else singles.add(val);
    });
    fours.sort((a, b) => b.compareTo(a)); threes.sort((a, b) => b.compareTo(a)); pairs.sort((a, b) => b.compareTo(a)); singles.sort((a, b) => b.compareTo(a));
    if (fours.isNotEmpty) return HandStrength(HandRank.fourOfAKind, [fours[0], ...singles]);
    if (threes.isNotEmpty && pairs.isNotEmpty) return HandStrength(HandRank.fullHouse, [threes[0], pairs[0]]);
    if (isFlush) return HandStrength(HandRank.flush, hand.map((c) => c.value).toList());
    if (isStraight) return HandStrength(HandRank.straight, [hand.first.value]);
    if (threes.isNotEmpty) return HandStrength(HandRank.threeOfAKind, [threes[0], ...singles]);
    if (pairs.length >= 2) return HandStrength(HandRank.twoPair, [pairs[0], pairs[1], ...singles]);
    if (pairs.length == 1) return HandStrength(HandRank.onePair, [pairs[0], ...singles]);
    return HandStrength(HandRank.highCard, hand.map((c) => c.value).toList());
  }
  static bool _isFlush(List<CardModel> hand) {
    Suit firstSuit = hand[0].suit;
    return hand.every((c) => c.suit == firstSuit);
  }
  static bool _isStraight(List<CardModel> hand) {
    if (hand[0].rank == Rank.ace && hand[1].rank == Rank.five && hand[4].rank == Rank.two) return true;
    for (int i = 0; i < hand.length - 1; i++) { if (hand[i].value - hand[i+1].value != 1) return false; }
    return true;
  }
}

class MonteCarloAI {
  static const int SIMULATION_COUNT = 600;

  static Future<Map<String, dynamic>> decideAction(
      List<CardModel> cpuHand, 
      List<CardModel> communityCards, 
      int pot, 
      int toCall,
      GamePhase phase, 
  ) async {
    return await Future.delayed(const Duration(milliseconds: 100), () {
      double winRate = _calculateWinRate(cpuHand, communityCards, phase);
      
      String action = "Fold";
      String reason = "";

      double requiredWinRate = 0.0;
      if (toCall > 0) {
        requiredWinRate = toCall / (pot + toCall);
      }
      
      bool isBluffing = winRate < 0.3 && Random().nextDouble() < 0.10;

      if (isBluffing) {
        action = 'Raise';
        reason = "Bluff!";
      } else {
        if (winRate > requiredWinRate + 0.20) {
          action = 'Raise';
          reason = "Value Raise";
        } else if (winRate > requiredWinRate) {
           action = 'Call';
           reason = "Odds Call";
        } else {
           if (toCall == 0) {
             action = 'Check';
             reason = "Free Check";
           } else {
             action = 'Fold';
             reason = "Bad Odds";
           }
        }
      }

      if (action == 'Fold' && toCall == 0) {
        action = 'Check';
        reason = "Free Check";
      }

      return {
        'action': action, 
        'winRate': winRate,
        'requiredWinRate': requiredWinRate,
        'reason': reason
      };
    });
  }

  static double _calculateWinRate(List<CardModel> cpuHand, List<CardModel> communityCards, GamePhase phase) {
    int wins = 0, ties = 0, total = SIMULATION_COUNT;
    List<CardModel> knownCards = [...cpuHand, ...communityCards];
    List<CardModel> deckBase = Deck.getRemainingCards(knownCards);
    int neededCommunity = 5 - communityCards.length;
    
    bool applyHandRangeBias = (phase != GamePhase.preFlop);

    for (int i = 0; i < total; i++) {
      List<CardModel> deck = List.from(deckBase)..shuffle();
      int deckIndex = 0;
      List<CardModel> opponentHand = [];
      
      if (applyHandRangeBias) {
        for (int retry = 0; retry < 3; retry++) {
          CardModel c1 = deck[deckIndex];
          CardModel c2 = deck[deckIndex + 1];
          bool isStrong = false;
          if (c1.rank == c2.rank) isStrong = true;
          else if (c1.value >= 10 && c2.value >= 10) isStrong = true;
          else if (c1.rank == Rank.ace || c2.rank == Rank.ace) isStrong = true;
          
          if (isStrong) {
            opponentHand = [c1, c2];
            deckIndex += 2;
            break;
          } else {
            if (retry < 2 && Random().nextDouble() < 0.7) { 
              deckIndex += 2; 
              if (deckIndex + 2 + neededCommunity > deck.length) {
                 opponentHand = [c1, c2];
                 deckIndex -= 2; 
                 deckIndex += 2;
                 break;
              }
              continue; 
            } else {
              opponentHand = [c1, c2];
              deckIndex += 2;
              break;
            }
          }
        }
        if (opponentHand.isEmpty) {
           opponentHand = [deck[0], deck[1]];
           deckIndex = 2;
        }

      } else {
        opponentHand = [deck[deckIndex++], deck[deckIndex++]];
      }

      List<CardModel> simCommunity = List.from(communityCards);
      for (int j = 0; j < neededCommunity; j++) {
        simCommunity.add(deck[deckIndex++]);
      }
      
      HandStrength cpuStrength = PokerEvaluator.evaluate([...cpuHand, ...simCommunity]);
      HandStrength oppStrength = PokerEvaluator.evaluate([...opponentHand, ...simCommunity]);
      int result = cpuStrength.compareTo(oppStrength);
      if (result > 0) wins++; else if (result == 0) ties++;
    }
    return (wins + (ties * 0.5)) / total;
  }
}

// ---------------------------------------------------------------------------
// Game Engine
// ---------------------------------------------------------------------------

class PokerGameEngine extends ChangeNotifier {
  Deck _deck = Deck();
  List<CardModel> playerHand = [];
  List<CardModel> cpuHand = [];
  List<CardModel> communityCards = [];
  GamePhase _phase = GamePhase.preFlop;
  String message = "ゲーム開始待機中";
  String cpuThought = "";
  
  int pot = 0;
  int playerStack = 1000;
  int cpuStack = 1000;
  int playerStreetBet = 0;
  int cpuStreetBet = 0;
  
  static const int smallBlind = 10;
  static const int bigBlind = 20;

  bool isPlayerTurn = false;
  bool isPlayerButton = true;
  bool _playerActed = false;
  bool _cpuActed = false;

  GamePhase get phase => _phase;
  bool get canCheck => playerStreetBet == cpuStreetBet;

  int get minRaiseAmount {
    int toCall = cpuStreetBet - playerStreetBet;
    if (playerStack <= toCall) return playerStack + playerStreetBet;
    int baseBet = cpuStreetBet > 0 ? cpuStreetBet : bigBlind;
    int minTotal = baseBet + bigBlind; 
    if (cpuStreetBet > 0) {
      minTotal = cpuStreetBet * 2;
    }
    return minTotal;
  }
  
  int get maxRaiseAmount => playerStack + playerStreetBet;

  void startNewGame() {
    _deck = Deck();
    playerHand = [_deck.draw(), _deck.draw()];
    cpuHand = [_deck.draw(), _deck.draw()];
    communityCards = [];
    _phase = GamePhase.preFlop;
    cpuThought = "";
    
    if (playerStack < bigBlind || cpuStack < bigBlind) {
      playerStack = 1000;
      cpuStack = 1000;
      message = "チップを補充しました！";
    }

    isPlayerButton = !isPlayerButton;
    pot = 0;
    playerStreetBet = 0;
    cpuStreetBet = 0;
    _playerActed = false;
    _cpuActed = false;

    if (isPlayerButton) {
      _betPlayer(smallBlind);
      _betCpu(bigBlind);
      isPlayerTurn = true;
      message = "あなたは Dealer(SB) です。";
    } else {
      _betCpu(smallBlind);
      _betPlayer(bigBlind);
      isPlayerTurn = false;
      message = "あなたは BB です。";
      Future.delayed(const Duration(seconds: 1), _cpuTurn);
    }
    notifyListeners();
  }

  void _betPlayer(int amount) {
    if (playerStack < amount) amount = playerStack;
    playerStack -= amount;
    playerStreetBet += amount;
    pot += amount;
  }

  void _betCpu(int amount) {
    if (cpuStack < amount) amount = cpuStack;
    cpuStack -= amount;
    cpuStreetBet += amount;
    pot += amount;
  }

  void playerAction(String actionType, {int? amount}) {
    if (!isPlayerTurn) return;

    int callAmount = cpuStreetBet - playerStreetBet;

    if (actionType == "Fold") {
      message = "プレイヤー Fold。CPUの勝ち！";
      _givePotToWinner(isPlayer: false);
      return;
    } else if (actionType == "Check") {
      if (!canCheck) return;
      message = "プレイヤー: Check";
    } else if (actionType == "Call") {
      _betPlayer(callAmount);
      message = "プレイヤー: Call ($callAmount)";
    } else if (actionType == "Raise") {
      int targetTotalBet = amount ?? (cpuStreetBet + bigBlind);
      int additionalChips = targetTotalBet - playerStreetBet;
      _betPlayer(additionalChips);
      message = "プレイヤー: Raise (Total $targetTotalBet)";
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

    int toCall = playerStreetBet - cpuStreetBet;

    final aiResult = await MonteCarloAI.decideAction(
      cpuHand, 
      communityCards, 
      pot, 
      toCall,
      _phase 
    );
    
    String action = aiResult['action'];
    double winRate = aiResult['winRate'];
    // ignore: unused_local_variable
    double requiredWinRate = aiResult['requiredWinRate'];
    String reason = aiResult['reason'];

    if (action == "Fold") {
      cpuThought = "勝率: ${(winRate * 100).toStringAsFixed(1)}% -> Fold\n($reason)";
      message = "CPU Fold。あなたの勝ち！";
      _givePotToWinner(isPlayer: true);
      notifyListeners();
      return;
    }

    if (action == "Check" || (action == "Call" && toCall == 0)) {
      action = "Check";
      message = "CPU: Check";
    } else if (action == "Call") {
      _betCpu(toCall);
      message = "CPU: Call";
    } else if (action == "Raise") {
      int added = (winRate > 0.8) ? pot : (pot ~/ 2);
      if (reason == "Bluff!") added = pot ~/ 2; 

      int raiseAmount = toCall + added;
      if (raiseAmount > playerStack + playerStreetBet) {
         raiseAmount = playerStack + playerStreetBet - cpuStreetBet;
      }
      if (raiseAmount < bigBlind) raiseAmount = bigBlind;

      _betCpu(raiseAmount);
      message = "CPU: Raise";
      _playerActed = false;
    }

    cpuThought = "勝率: ${(winRate * 100).toStringAsFixed(1)}%\n判断: $action\n($reason)";
    
    _cpuActed = true;
    isPlayerTurn = true;
    notifyListeners();
    _checkNextPhaseOrTurn();
  }

  void _checkNextPhaseOrTurn() {
    bool amountsEqual = playerStreetBet == cpuStreetBet;
    bool isAllIn = playerStack == 0 || cpuStack == 0;
    if ((_playerActed && _cpuActed && amountsEqual) || (_playerActed && _cpuActed && isAllIn)) {
      Future.delayed(const Duration(milliseconds: 800), _nextPhase);
    } else {
      if (isPlayerTurn) message = "あなたのアクションです";
      else Future.delayed(const Duration(milliseconds: 800), _cpuTurn);
      notifyListeners();
    }
  }

  void _nextPhase() {
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
    if (isPlayer) playerStack += pot; else cpuStack += pot;
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
      resultText = "引き分け！";
      playerStack += pot ~/ 2;
      cpuStack += pot ~/ 2;
    }
    pot = 0;
    message = "$resultText\nYou:${playerResult.toString()} vs CPU:${cpuResult.toString()}";
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// UI Widgets
// ---------------------------------------------------------------------------

class PokerTablePage extends StatefulWidget {
  const PokerTablePage({super.key});
  @override
  State<PokerTablePage> createState() => _PokerTablePageState();
}

class _PokerTablePageState extends State<PokerTablePage> {
  final PokerGameEngine _game = PokerGameEngine();
  
  bool _isRaising = false;
  double _currentSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _game.addListener(() { setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) { _game.startNewGame(); });
  }
  
  // クリック音を再生するヘルパー関数
  void _playClickSound() {
    SystemSound.play(SystemSoundType.click);
  }

  void _toggleRaiseMode() {
    _playClickSound(); // 音を再生
    setState(() {
      _isRaising = !_isRaising;
      if (_isRaising) {
        double minRaise = _game.minRaiseAmount.toDouble();
        double maxRaise = _game.maxRaiseAmount.toDouble();
        if (minRaise > maxRaise) minRaise = maxRaise;
        _currentSliderValue = minRaise;
      }
    });
  }

  void _confirmRaise() {
    _playClickSound(); // 音を再生
    _game.playerAction("Raise", amount: _currentSliderValue.toInt());
    setState(() {
      _isRaising = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool canCheck = _game.canCheck;
    int toCall = _game.cpuStreetBet - _game.playerStreetBet;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // CPU Area
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8), // パディングを縮小
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StackInfoWidget(name: "CPU", stack: _game.cpuStack, isDealer: !_game.isPlayerButton),
                    const SizedBox(height: 4), // 隙間を縮小
                    // CPU思考表示を削除
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _game.phase == GamePhase.showDown
                          ? _game.cpuHand.map((c) => CardWidget(card: c)).toList()
                          : [const CardBackWidget(), const SizedBox(width: 8), const CardBackWidget()],
                    ),
                    if (_game.cpuStreetBet > 0) 
                      Padding(
                        padding: const EdgeInsets.only(top: 4), // マージン調整
                        child: ChipPilesWidget(amount: _game.cpuStreetBet)
                      ),
                  ],
                ),
              ),
            ),
            
            // Community Cards
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Pot: \$${_game.pot}", style: const TextStyle(color: Colors.yellow, fontSize: 24, fontWeight: FontWeight.bold)), // フォント少し小さく
                  const SizedBox(height: 8), // 隙間を縮小
                  SizedBox(
                    height: 80, // カード表示エリアを少し小さく
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _game.communityCards.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: CardWidget(card: c))).toList(),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                    child: Text(_game.message, style: const TextStyle(color: Colors.white, fontSize: 13)), // フォント調整
                  ),
                ],
              ),
            ),

            // Player Area
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(12), // パディング縮小
                color: Colors.black26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_game.playerStreetBet > 0) 
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChipPilesWidget(amount: _game.playerStreetBet)
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _game.playerHand.map((c) => CardWidget(card: c)).toList(),
                    ),
                    const SizedBox(height: 8),
                    StackInfoWidget(name: "YOU", stack: _game.playerStack, isDealer: _game.isPlayerButton),
                    const SizedBox(height: 12),
                    
                    // Action Area
                    if (_game.phase == GamePhase.showDown)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow), label: const Text("Next Hand"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        onPressed: () {
                          _playClickSound(); // 音を再生
                          _game.startNewGame();
                        }, 
                      )
                    else if (_isRaising)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Raise to: \$${_currentSliderValue.toInt()}", 
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                            ),
                            Slider(
                              value: _currentSliderValue,
                              min: _game.minRaiseAmount.toDouble(),
                              max: _game.maxRaiseAmount.toDouble(),
                              activeColor: Colors.orange,
                              inactiveColor: Colors.grey,
                              onChanged: (val) => setState(() => _currentSliderValue = val),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _toggleRaiseMode, 
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                                  child: const Text("Cancel"),
                                ),
                                ElevatedButton(
                                  onPressed: _confirmRaise, 
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                  child: Text(_currentSliderValue.toInt() == _game.maxRaiseAmount ? "ALL IN!" : "Confirm"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ActionButton(label: "Fold", color: Colors.red[900]!, onPressed: () => _game.playerAction("Fold")),
                          ActionButton(label: canCheck ? "Check" : "Call \$$toCall", color: Colors.blue[800]!, onPressed: () => _game.playerAction(canCheck ? "Check" : "Call")),
                          ActionButton(label: "Raise", color: Colors.orange[800]!, onPressed: _toggleRaiseMode),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// UI Components
class StackInfoWidget extends StatelessWidget {
  final String name; final int stack; final bool isDealer;
  const StackInfoWidget({super.key, required this.name, required this.stack, required this.isDealer});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDealer) Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Text("D", style: TextStyle(fontWeight: FontWeight.bold))),
        const SizedBox(width: 8),
        Column(children: [Text(name, style: const TextStyle(color: Colors.white70)), Text("\$$stack", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]),
      ],
    );
  }
}
class ChipPilesWidget extends StatelessWidget {
  final int amount;
  const ChipPilesWidget({super.key, required this.amount});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.yellow[800], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white38)), child: Text("\$$amount", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)));
  }
}
class CardWidget extends StatelessWidget {
  final CardModel card;
  const CardWidget({super.key, required this.card});
  @override
  Widget build(BuildContext context) {
    return Container(width: 50, height: 75, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(1, 1), blurRadius: 2)]), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(card.displayRank, style: TextStyle(color: card.color, fontSize: 18, fontWeight: FontWeight.bold)), Text(card.suitSymbol, style: TextStyle(color: card.color, fontSize: 20))]));
  }
}
class CardBackWidget extends StatelessWidget {
  const CardBackWidget({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(width: 50, height: 75, decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white, width: 2)), child: const Center(child: Icon(Icons.pattern, color: Colors.white24, size: 20)));
  }
}
class ActionButton extends StatelessWidget {
  final String label; final Color color; final VoidCallback onPressed;
  const ActionButton({super.key, required this.label, required this.color, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color, 
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
      ), 
      onPressed: () {
        SystemSound.play(SystemSoundType.click); // 音を鳴らす
        onPressed();
      }, 
      child: Text(label, style: const TextStyle(color: Colors.white))
    );
  }
}