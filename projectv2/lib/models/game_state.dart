// lib/models/game_state.dart

import 'dart:math';
import '../utils/constants.dart';
import 'card.dart';

class GameState {
  List<double> stacks = [0.0, 0.0]; // [AI 스택, 내 스택]
  List<double> bets = [0.0, 0.0]; // [AI 베팅, 내 베팅]
  List<double> contrib = [0.0, 0.0]; // 이번 라운드 총 투자금
  List<GameCard> hands = [];
  List<Act> history = []; // 행동 기록

  double pot = 0.0;
  int turn = 1; // 0: AI, 1: Me
  bool done = false;
  bool wasCarried = false;

  // [수정됨 1] 마지막으로 공격적 액션(Bet, Raise, All-in)을 취한 플레이어
  // -1: 아무도 안 함 (Check-Check 중), 0: AI, 1: Player
  int lastAggressor = -1;

  // 생성자
  GameState({
    required double s0, // AI Chip
    required double s1, // My Chip
    GameCard? h1, // AI Card (Nullable)
    GameCard? h2, // My Card (Nullable)
    double ante = 1.0,
    double carriedPot = 0.0,
    this.lastAggressor = -1, // [수정됨 1] 초기값
  }) {
    // 카드가 없으면(null) 학습용 랜덤 카드 생성
    if (h1 != null && h2 != null) {
      hands = [h1, h2];
    } else {
      var r = Random();
      int r1 = ranks[r.nextInt(10)];
      int r2 = ranks[r.nextInt(10)];
      hands = [GameCard(rank: r1, suit: 's'), GameCard(rank: r2, suit: 'h')];
    }

    // Ante(참가비) 처리
    double a0 = min(s0, ante);
    double a1 = min(s1, ante);

    stacks = [s0 - a0, s1 - a1];
    bets = [a0, a1];
    contrib = [a0, a1];

    pot = a0 + a1 + carriedPot;
    wasCarried = carriedPot > 0;

    history = [];
    turn = 1; // 플레이어 먼저 시작 (기본값)
    done = false;
  }

  // 유효한 행동 계산 (기존 유지)
  List<Act> validActs() {
    int me = turn;
    int opp = 1 - me;

    if (stacks[me] <= 0) return [Act.fold, Act.check];

    List<Act> acts = [Act.fold, Act.check];
    double diff = bets[opp] - bets[me];
    double target = pot + diff;

    for (var act in [Act.betHalf, Act.betPot, Act.allIn]) {
      if (act == Act.allIn) {
        acts.add(act);
        continue;
      }

      double raise = target * betMults[act]!;
      if (diff + raise < stacks[me] && raise >= 1) {
        acts.add(act);
      }
    }
    return acts;
  }

  // 행동 적용
  void apply(Act act, {double customAmt = -1}) {
    history.add(act);

    if (act == Act.fold) {
      done = true;
      return;
    }

    // [수정됨 2] 공격적 액션인지 판단하여 Aggressor 갱신
    if (act == Act.betHalf ||
        act == Act.betPot ||
        act == Act.allIn ||
        act == Act.overBet ||
        (customAmt > 0 && customAmt > bets[1 - turn])) {
      // 커스텀 베팅으로 레이즈한 경우도 포함
      lastAggressor = turn;
    }
    // 주의: Call(Check), Fold는 Aggressor를 바꾸지 않음 (기존 주도권 유지)

    int me = turn;
    int opp = 1 - me;
    double diff = bets[opp] - bets[me];
    double amt = 0.0;

    if (customAmt > 0) {
      double effectiveMax = stacks[opp] + diff;
      amt = min(stacks[me], min(customAmt, effectiveMax));
    } else {
      if (act == Act.check) {
        amt = min(diff, stacks[me]);
      } else if (act == Act.allIn) {
        double myTotal = stacks[me] + bets[me];
        double oppTotal = stacks[opp] + bets[opp];
        double effectiveStack = min(myTotal, oppTotal);
        amt = effectiveStack - bets[me];
        if (amt < 0) amt = 0;
      } else {
        double mult = betMults[act] ?? 0;
        double raise = (pot + diff) * mult;
        amt = min(stacks[me], diff + raise.floorToDouble());
      }
    }

    stacks[me] -= amt;
    bets[me] += amt;
    contrib[me] += amt;
    pot += amt;

    // 종료 조건 검사
    if (stacks[opp] <= 0 && bets[me] >= bets[opp]) {
      done = true;
    } else if (stacks[me] <= 0 && bets[opp] >= bets[me]) {
      done = true;
    } else if (bets[0] == bets[1] && history.length >= 1) {
      if (act == Act.check ||
          act == Act.fold ||
          diff > 0 ||
          (customAmt == diff)) {
        if (history.length >= 2 || diff > 0) {
          done = true;
        }
      }
    }

    if (!done) {
      turn = opp;
    }
  }

  // 승패 보상 계산 (기존 유지)
  double payoff(int p) {
    int opp = 1 - p;
    Act last = history.last;

    if (last == Act.fold) {
      int folder = turn;
      double penalty = (hands[folder].rank == 10) ? 10.0 : 0.0;

      if (p == (1 - folder)) {
        return (pot - contrib[p]) + penalty;
      } else {
        return -contrib[p] - penalty;
      }
    }

    int r1 = hands[p].rank;
    int r2 = hands[opp].rank;

    if (r1 == 1 && r2 == 10) return pot - contrib[p];
    if (r1 == 10 && r2 == 1) return -contrib[p];
    if (r1 > r2) return pot - contrib[p];
    if (r1 < r2) return -contrib[p];

    return 0.0;
  }

  // 시뮬레이션용 깊은 복사
  GameState clone() {
    var s = GameState(
      s0: 0,
      s1: 0,
      h1: GameCard.clone(hands[0]),
      h2: GameCard.clone(hands[1]),
      // [수정됨 3] clone 시에도 lastAggressor 전달 필요 (생성자에 추가했으므로)
      lastAggressor: lastAggressor,
    );

    s.stacks = List.from(stacks);
    s.bets = List.from(bets);
    s.pot = pot;
    s.contrib = List.from(contrib);
    s.history = List.from(history);
    s.turn = turn;
    s.done = done;

    return s;
  }
}
