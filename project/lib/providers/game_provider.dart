import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../models/card.dart';
import '../models/deck.dart';
import '../models/game_state.dart';
import '../models/user_stats.dart';
import '../logic/solver.dart';
import '../logic/hand_analyzer.dart';

class GameProvider with ChangeNotifier {
  // --- 1. 상태 변수들 ---
  final Deck _deck = Deck();
  final Solver _solver = Solver();
  final UserStats _userStats = UserStats();
  bool _isGameOver = false;
  bool get isGameOver => _isGameOver;

  GameState? _gameState;
  List<double> _chips = [initialChips, initialChips]; // [AI, Me]
  int _round = 0;
  double _carriedPot = 0.0;

  // AI 기분 관련
  String _aiMoodText = "🤖 Normal";
  double _moodAggro = 1.0;
  double _moodFear = 0.0;

  // UI 표시용
  final List<String> _logs = []; // 게임 로그
  bool _isThinking = false; // AI 로딩 중?
  String _aiThoughText = "Waiting..."; // AI 생각 텍스트 (승률 등)
  double _aiWinRate = 0.5; // 승률 바 표시용
  bool _showHeroCall = false; // 히어로 콜 배지 표시
  bool _showRisk = false; // 10 리스크 배지 표시
  bool _triggerConfetti = false; // 폭죽 효과 트리거

  // Getters
  GameState? get gameState => _gameState;
  List<double> get chips => _chips;
  int get round => _round;
  double get carriedPot => _carriedPot;
  String get aiMoodText => _aiMoodText;
  List<String> get logs => _logs;
  bool get isThinking => _isThinking;
  String get aiThoughtText => _aiThoughText;
  double get aiWinRate => _aiWinRate;
  bool get showHeroCall => _showHeroCall;
  bool get showRisk => _showRisk;
  bool get triggerConfetti => _triggerConfetti;

  // --- 2. 초기화 및 게임 시작 ---

  Future<void> initGame() async {
    log("🧠 Neural Network Training...", "sys");
    // 초기 학습 (500회) - 실제 앱에선 로딩 화면 보여주며 실행
    await _solver.train(trainingIterations, (progress) {
      // 진행률 업데이트 필요 시 구현
    });
    log("✅ Training Complete!", "sys");

    _deck.init();
    startRound();
  }

  void startRound() {
    // 게임 종료 조건 체크
    if (_chips[0] <= 0 || _chips[1] <= 0) {
      String winner = _chips[0] <= 0 ? "🎉 YOU WIN!" : "💀 YOU LOSE!";
      log("GAME OVER: $winner", "warn");
      return;
    }

    _round++;
    _userStats.totalHands++;

    // UI 초기화
    _isThinking = false;
    _showHeroCall = false;
    _showRisk = false;
    _triggerConfetti = false;
    _aiThoughText = "Waiting...";

    // 1. Ante(판돈) 계산
    double currentAnte = 2.0;
    if (_round > 5 && _round <= 20) {
      currentAnte = 3.0;
    } else if (_round > 20) {
      currentAnte = 4.0;
    }

    log("--- Round $_round (Ante: ${currentAnte.toInt()}) ---", "sys");

    // 2. 카드 드로우
    GameCard h1 = _deck.draw();
    GameCard h2 = _deck.draw();

    // 3. 게임 상태 생성 (AI 선공 여부 랜덤)
    _gameState = GameState(
      s0: _chips[0],
      s1: _chips[1],
      h1: h1,
      h2: h2,
      ante: currentAnte,
      carriedPot: _carriedPot,
    );
    _carriedPot = 0.0; // 이월 팟 초기화
    _chips[0] -= currentAnte; // AI 참가비 차감
    _chips[1] -= currentAnte; // 내 참가비 차감

    // 화면 갱신 (참가비 빠진 거 보여주기 위해)
    notifyListeners();
    // AI 턴이면 바로 시작
    if (_gameState!.turn == 0) {
      runAI();
    } else {
      notifyListeners();
    }
  }

  void restartGame() {
    _chips = [initialChips, initialChips]; // 칩 초기화
    _round = 0;
    _isGameOver = false;
    _logs.clear();
    _userStats.reset(); // 통계 초기화
    _deck.init(); // 덱 초기화

    log("🔄 Game Restarted!", "sys");
    startRound();
    notifyListeners();
  }

  // --- 3. AI 로직 (핵심) ---

  Future<void> runAI() async {
    if (_gameState == null || _gameState!.done) return;

    _isThinking = true;
    notifyListeners();

    // 1. 핸드 분석
    // unknownPool: 덱에 남은 카드 + 내 머리 위의 카드(hands[0])
    List<GameCard> unknownPool = [..._deck.cards, _gameState!.hands[0]];
    int playerRank = _gameState!.hands[1].rank; // 상대(플레이어) 카드

    var analysis = analyzeHand(playerRank, unknownPool);
    double equity = analysis.equity;
    double probTen = analysis.probTen;

    // UI 업데이트 (승률 표시)
    _aiWinRate = equity;
    _aiThoughText = "Win Rate: ${(equity * 100).toStringAsFixed(0)}%";
    _showRisk = probTen > 0.1; // 10 리스크 표시

    notifyListeners();

    // 2. 생각하는 척 딜레이
    await Future.delayed(Duration(milliseconds: 600 + Random().nextInt(800)));

    // 3. Solver 전략 가져오기
    String key =
        "Opp:$playerRank|Seq:${_gameState!.history.map((e) => e.index).join('')}";
    List<double> strat = _solver
        .getNode(key)
        .getAvgStrat(); // [Fold, Check, ...]
    List<Act> valid = _gameState!.validActs();

    // 4. 상황 판단 변수 계산
    int me = _gameState!.turn; // 0
    int opp = 1 - me; // 1

    // Pot Odds 및 Effective Stack
    double myMax = _gameState!.stacks[me] + _gameState!.bets[me];
    double oppMax = _gameState!.stacks[opp] + _gameState!.bets[opp];
    double effectiveStack = min(myMax, oppMax);
    double amountToMatch = min(effectiveStack, _gameState!.bets[opp]);
    double toCall = max(0, amountToMatch - _gameState!.bets[me]);
    double finalPotSize = _gameState!.pot + toCall;
    double requiredEquity = finalPotSize > 0 ? toCall / finalPotSize : 0;

    // === [FIX 1] Endgame God Mode (카드 카운팅) ===
    bool isCertainty = unknownPool.length <= 3;
    if (isCertainty) {
      if (equity >= 0.99) {
        strat[Act.fold.index] = 0.0;
        strat[Act.allIn.index] = 1000.0;
        strat[Act.betPot.index] = 500.0;
      } else if (equity <= 0.01 && probTen < 0.01) {
        strat[Act.fold.index] = 1000.0;
        strat[Act.check.index] = 0.0;
      }
    }

    // === [FIX 2] Deep Stack Protection ===
    if (requiredEquity > 0.4 && !isCertainty) {
      if (equity < 0.6) {
        strat[Act.fold.index] *= 1.5;
      }
    }

    // === Hero Call (블러핑 감지) ===
    // 상대의 공격성 카운트
    int aggroCount = 0;
    int hLen = _gameState!.history.length;
    // 최근 기록 확인
    if (hLen >= 1 &&
        [
          Act.betHalf,
          Act.betPot,
          Act.overBet,
          Act.allIn,
        ].contains(_gameState!.history.last)) {
      aggroCount++;
    }
    if (hLen >= 3 &&
        [
          Act.betHalf,
          Act.betPot,
          Act.overBet,
          Act.allIn,
        ].contains(_gameState!.history[hLen - 3])) {
      aggroCount++;
    }

    double effectiveBluffRate = _userStats.getBluffRate();
    if (aggroCount >= 1) effectiveBluffRate += 0.15;
    if (aggroCount >= 2) effectiveBluffRate += 0.10;

    if (effectiveBluffRate > 0.3 &&
        equity > 0.3 &&
        equity < 0.65 &&
        requiredEquity > 0.3) {
      double heroFactor = effectiveBluffRate > 0.45 ? 0.7 : 0.5;
      double shift = strat[Act.fold.index] * heroFactor;
      strat[Act.fold.index] -= shift;

      if (valid.contains(Act.check)) {
        strat[Act.check.index] += shift;
      }
      _showHeroCall = true; // 배지 표시
    }

    // === [FIX 3] AI Mood & Desperate Fight ===
    _updateAIMood(equity); // 기분 업데이트

    // Bias 계산
    double bias = (equity - 0.5) * 2.4 * _moodAggro;
    if (isCertainty && equity > 0.99) bias = 10.0;

    if (bias > 0) {
      // 유리함: 공격적
      for (var a in [Act.betHalf, Act.betPot, Act.allIn]) {
        if (valid.contains(a)) strat[a.index] *= (1 + bias * 1.5);
      }
      if (valid.contains(Act.fold)) strat[Act.fold.index] *= (1 - bias * 0.8);
    } else {
      // 불리함: 수비적
      double def = bias.abs();
      if (valid.contains(Act.fold)) strat[Act.fold.index] *= (1 + def * 2.0);
      for (var a in [Act.betHalf, Act.betPot, Act.allIn]) {
        if (valid.contains(a)) strat[a.index] *= (1 - def * 0.8);
      }
    }

    // === 10 패널티 회피 ===
    double effectiveFearThreshold = 0.1 - _moodFear;
    if (!isCertainty &&
        probTen > effectiveFearThreshold &&
        valid.contains(Act.fold)) {
      double penaltyFactor = min(max(probTen - 0.1, 0) * 2.5, 0.8);
      double foldProb = strat[Act.fold.index];
      double reduceAmount = foldProb * penaltyFactor;

      strat[Act.fold.index] -= reduceAmount;
      Act safeOption = valid.contains(Act.check)
          ? Act.check
          : (valid.contains(Act.betHalf) ? Act.betHalf : Act.fold);

      if (safeOption != Act.fold) strat[safeOption.index] += reduceAmount;
      strat[Act.fold.index] = max(strat[Act.fold.index], 0.05);
    }

    // === 유저 성향 대응 ===
    if (_userStats.totalHands >= 5) {
      double diff = _userStats.getFoldRate() - 0.4;
      double mult = min(max(1.0 + (diff * 0.5), 0.6), 1.5);
      for (var a in [Act.betHalf, Act.betPot, Act.allIn]) {
        if (valid.contains(a)) strat[a.index] *= mult;
      }
    }

    // 5. 최종 행동 결정 (Roulette Wheel Selection)
    double vSum = 0.0;
    for (var act in valid) {
      vSum += strat[act.index];
    }

    Act action = valid.contains(Act.check) ? Act.check : Act.fold;
    if (vSum > 0) {
      double r = Random().nextDouble();
      double cum = 0.0;
      for (var act in valid) {
        cum += strat[act.index] / vSum;
        if (r <= cum) {
          action = act;
          break;
        }
      }
    }

    // 행동 적용
    log("🤖 AI: ${actText[action]}", "ai");
    double oldBet = _gameState!.bets[0];
    _gameState!.apply(action);
    double newBet = _gameState!.bets[0];
    _chips[0] -= (newBet - oldBet);
    _isThinking = false;

    notifyListeners();

    if (_gameState!.done) {
      endRound();
    } else {
      // 아직 안 끝났으면 내 턴 (UI 업데이트)
    }
  }

  // --- 4. 내부 로직 헬퍼 ---

  // [수정] 자산 평가 로직 개선
  // providers/game_provider.dart 내부

  void _updateAIMood(double equity) {
    if (_gameState == null) return;

    double aiTotal = _gameState!.stacks[0] + _gameState!.bets[0];
    double playerTotal = _gameState!.stacks[1] + _gameState!.bets[1];
    double diff = aiTotal - playerTotal;

    // 1. 압도적 우세 (기존 유지)
    if (diff > 50) {
      _aiMoodText = "😈 Dominating";
      _moodAggro = 1.2;
      _moodFear = -0.05;
    }
    // 2. 리드 중 (기존 유지)
    else if (diff > 10) {
      _aiMoodText = "😎 Leading";
      _moodAggro = 1.1;
      _moodFear = 0.0;
    }
    // 3. [수정됨] 생존 모드 (칩이 매우 적음, -50 이하)
    else if (diff < -50) {
      // ★ 핵심 수정: 칩은 없지만 패가 좋을 때 (승률 70% 이상)
      if (equity > 0.7) {
        _aiMoodText = "🔥 All or Nothing"; // 이판사판
        _moodAggro = 1.5; // 공격성 극대화 (1.6배) -> 올인 유도
        _moodFear = -0.2; // 공포심 제거 (10 패널티 무시하고 지름)
      } else {
        // 패도 구리면 납작 엎드림
        _aiMoodText = "🆘 Survival";
        _moodAggro = 0.88; // 더 수비적으로 (0.8 -> 0.7)
        _moodFear = 0.15;
      }
    }
    // 4. [수정됨] 약간 불리함 (-10 이하)
    else if (diff < -10) {
      // 여기서도 패가 꽤 좋으면 (승률 65% 이상) 역전 시도
      if (equity > 0.65) {
        _aiMoodText = "🥊 Counter Punch"; // 카운터 펀치
        _moodAggro = 1.2; // 꽤 공격적
        _moodFear = -0.1;
      } else {
        _aiMoodText = "🤔 Analyzing";
        _moodAggro = 0.92;
        _moodFear = 0.05;
      }
    }
    // 5. 비슷비슷함 (기존 유지)
    else {
      if (equity > 0.6) {
        _aiMoodText = "🦁 Confident";
        _moodAggro = 1.1;
      } else {
        _aiMoodText = "🤖 Neutral";
        _moodAggro = 1.0;
      }
      _moodFear = 0.0;
    }
  }

  // --- 5. 플레이어 액션 ---

  // [수정] 버튼 액션 즉시 반영
  void playerAct(Act action) {
    if (_gameState == null || _gameState!.turn != 1) return;

    if (action == Act.fold) _userStats.foldCount++;

    log("👤 You: ${actText[action]}", "user");
    double oldBet = _gameState!.bets[1];
    // 1. 로직 적용 (여기서 내부적으로 stack이 줄고 bet이 늘어남)
    _gameState!.apply(action);
    double newBet = _gameState!.bets[1];
    double diff = newBet - oldBet; // 이번 턴에 추가로 낸 돈
    _chips[1] -= diff;

    // 2. [핵심] UI 즉시 갱신! (AI가 생각하기 전에 화면부터 그림)
    notifyListeners();

    // 3. 게임 진행 (AI 턴이면 runAI 호출)
    if (_gameState!.done) {
      endRound();
    } else {
      // 화면이 갱신된 후 아주 잠깐 텀을 줘서 자연스럽게 연결
      Future.delayed(const Duration(milliseconds: 50), () {
        runAI();
      });
    }
  }

  // [수정] 슬라이더 베팅 즉시 반영
  void playerBetCustom(double amount) {
    if (_gameState == null || _gameState!.turn != 1) return;

    Act aiAct = Act.betPot;
    if (amount == _gameState!.stacks[1]) aiAct = Act.allIn;

    log("👤 You: Bet ${amount.toInt()}", "user");
    double oldBet = _gameState!.bets[1];
    // 1. 로직 적용
    _gameState!.apply(aiAct, customAmt: amount);
    double newBet = _gameState!.bets[1];
    double diff = newBet - oldBet;
    _chips[1] -= diff;
    // 2. [핵심] UI 즉시 갱신!
    notifyListeners();

    // 3. 게임 진행
    if (_gameState!.done) {
      endRound();
    } else {
      Future.delayed(const Duration(milliseconds: 50), () {
        runAI();
      });
    }
  }

  // --- 6. 라운드 종료 및 정산 (FIX 포함) ---

  void endRound() async {
    // 카드 공개 UI 처리 (필요시)
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500)); // 잠깐 대기

    GameCard c0 = _gameState!.hands[0];
    GameCard c1 = _gameState!.hands[1];

    // 1. 승패 판정
    int winner = -1; // -1: Draw, 0: AI, 1: You
    Act lastAct = _gameState!.history.last;

    if (lastAct == Act.fold) {
      winner = 1 - _gameState!.turn; // 폴드한 사람의 반대편 승리
    } else {
      // 쇼다운
      if (c0.rank == 1 && c1.rank == 10) {
        winner = 0;
      } // AI Revolution
      else if (c0.rank == 10 && c1.rank == 1) {
        winner = 1;
      } // My Revolution
      else if (c0.rank > c1.rank) {
        winner = 0;
      } else if (c1.rank > c0.rank) {
        winner = 1;
      }
    }

    // 2. 칩 정산 준비 (투자금 차감)
    //_chips[0] -= _gameState!.contrib[0];
    //_chips[1] -= _gameState!.contrib[1];

    // 10 페널티 처리
    if (lastAct == Act.fold) {
      int folder = _gameState!.turn;
      if (_gameState!.hands[folder].rank == 10) {
        log("🚨 10-Holding Penalty! (-10)", "warn");
        if (folder == 0) {
          _chips[0] -= 10;
          _chips[1] += 10;
        } else {
          _chips[1] -= 10;
          _chips[0] += 10;
        }
      }
    }

    // 3. Uncalled Bet 환불 (Excess)
    double excess = (_gameState!.contrib[0] - _gameState!.contrib[1]).abs();
    double refund0 = 0, refund1 = 0;

    if (_gameState!.contrib[0] > _gameState!.contrib[1]) {
      _chips[0] += excess;
      refund0 = excess;
    } else {
      _chips[1] += excess;
      refund1 = excess;
    }

    double mainPot = _gameState!.pot - excess;

    // 4. 통계 및 배지
    if (lastAct != Act.fold) {
      if (winner == 0) {
        // AI가 이김 (쇼다운)
        if (c1.rank <= 6 && _gameState!.contrib[1] > 10) {
          _userStats.bluffOpportunities++;
          _userStats.bluffsDetected++;
          log("🕵️ Bluff Detected!", "sys");
        } else {
          _userStats.bluffOpportunities++;
        }
      }
    }

    // 5. 팟 분배
    if (winner == 0) {
      _chips[0] += mainPot;
      _carriedPot = 0;
      double profit = (mainPot + refund0) - _gameState!.contrib[0];
      log("💀 LOSE (AI +${profit.toInt()})", "ai");
    } else if (winner == 1) {
      _chips[1] += mainPot;
      _carriedPot = 0;
      double profit = (mainPot + refund1) - _gameState!.contrib[1];
      log("🎉 WIN (+${profit.toInt()})", "user");

      // 폭죽 효과 트리거
      _triggerConfetti = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      _triggerConfetti = false;
    } else {
      // Draw logic
      if (_chips[0] < 1 || _chips[1] < 1) {
        log("🤝 All-in Draw! Split.", "sys");
        _chips[0] += (mainPot / 2).floor();
        _chips[1] += (mainPot / 2).floor();
        _carriedPot = 0;
      } else {
        log("🤝 DRAW - Pot Carried Over!", "sys");
        _carriedPot = mainPot;
      }
    }

    notifyListeners();

    if (_chips[0] < 1 || _chips[1] < 1) {
      _isGameOver = true; // 플래그 세팅
      String winner = _chips[0] < 1 ? "🎉 YOU WIN!" : "💀 GAME OVER";
      log(winner, "warn");
      notifyListeners(); // UI에 알림 -> 팝업 트리거
    } else {
      // 게임이 안 끝났으면 다음 라운드 진행
      await Future.delayed(const Duration(seconds: 3));
      if (!_isGameOver) {
        // 혹시 그 사이 재시작 눌렀을까봐 체크
        startRound();
      }
    }
  }

  void log(String msg, String type) {
    // UI에 보여줄 로그 포맷팅
    // 실제 앱에선 색상 처리를 위해 객체로 저장하는 게 좋음
    String prefix = "";
    if (type == "ai") {
      prefix = "";
    } else if (type == "user") {
      prefix = "";
    } else if (type == "warn") {
      prefix = "!! ";
    }

    _logs.add("$prefix$msg");
    if (_logs.length > 50) _logs.removeAt(0); // 로그제한
    notifyListeners();
  }
}
