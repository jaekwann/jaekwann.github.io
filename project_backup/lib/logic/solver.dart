// lib/logic/solver.dart

import 'dart:math';
import 'package:flutter/foundation.dart'; // debugPrint용
import '../utils/constants.dart';
import '../models/game_state.dart';

// 행동 개수 (Fold, Check, BetHalf 등 Enum 개수)
final int ACTION_COUNT = Act.values.length;

/// CFR 노드: 특정 상황(InfoSet)에서의 전략과 후회값을 저장
class Node {
  List<double> r = List.filled(ACTION_COUNT, 0.0); // Regret Sum
  List<double> s = List.filled(ACTION_COUNT, 0.0); // Strategy Sum (평균 전략용)

  /// [수정됨] epsilon(탐색 상수)을 파라미터로 받음
  /// 학습 초반에는 탐색을 많이 하고, 후반에는 줄여서 수렴 유도
  List<double> getStrat(double epsilon) {
    double sum = 0.0;
    List<double> strat = List.filled(ACTION_COUNT, 0.0);

    for (int i = 0; i < ACTION_COUNT; i++) {
      // Regret Matching: 양수 Regret에 비례하여 확률 배분
      // + epsilon: 탐색(Exploration)을 위한 노이즈 추가
      double val = max(r[i], 0.0) + epsilon;
      strat[i] = val;
      sum += val;
    }

    // 정규화 (확률 합 1.0 만들기)
    if (sum > 0) {
      for (int i = 0; i < ACTION_COUNT; i++) {
        strat[i] /= sum;
      }
    } else {
      // Regret이 모두 음수거나 0이면 균등 분포
      double uniform = 1.0 / ACTION_COUNT;
      for (int i = 0; i < ACTION_COUNT; i++) {
        strat[i] = uniform;
      }
    }
    return strat;
  }

  /// 학습된 최종 평균 전략 반환 (실전 AI 사용)
  List<double> getAvgStrat() {
    double sum = s.fold(0.0, (a, b) => a + b);
    List<double> avgStrat = List.filled(ACTION_COUNT, 0.0);

    if (sum > 0) {
      for (int i = 0; i < ACTION_COUNT; i++) {
        avgStrat[i] = s[i] / sum;
      }
    } else {
      double uniform = 1.0 / ACTION_COUNT;
      for (int i = 0; i < ACTION_COUNT; i++) {
        avgStrat[i] = uniform;
      }
    }
    return avgStrat;
  }
}

/// 인디언 포커 전용 Solver (Linear CFR + Epsilon Decay + Initiative Logic)
class Solver {
  Map<String, Node> nodes = {};

  // [최적화] Random 객체를 멤버 변수로 선언하여 재사용 (성능 향상)
  final Random _rng = Random();

  Node getNode(String key) => nodes.putIfAbsent(key, () => Node());

  /// 평균 후회값 계산 (학습 진행상황 파악용)
  double computeAverageRegret() {
    double sum = 0.0;
    int count = 0;
    for (var node in nodes.values) {
      for (double r in node.r) {
        sum += r;
        count++;
      }
    }
    return count > 0 ? sum / count : 0.0;
  }

  /// 최대 후회값 계산
  double computeMaxRegret() {
    double maxR = 0.0;
    for (var node in nodes.values) {
      for (double r in node.r) {
        if (r > maxR) maxR = r;
      }
    }
    return maxR;
  }

  /// 메인 학습 함수
  Future<void> train(int iters, Function(double)? onProgress) async {
    nodes.clear();
    debugPrint("🚀 Training Started with Optimized Linear CFR...");

    // 100번 단위로 배치 실행
    for (int i = 0; i < iters; i += 100) {
      // [수정됨] Epsilon Decay: 학습 진행률에 따라 탐색 범위를 줄임
      // 시작: 0.2 -> 끝: 0.0001 (제곱 그래프로 부드럽게 감소)
      double progress = i / iters;
      double epsilon = 0.2 * (1.0 - progress) * (1.0 - progress);
      if (epsilon < 0.0001) epsilon = 0.0001;

      for (int j = 0; j < 100; j++) {
        // [최적화] _rng 멤버 변수 사용
        double s0 = (_rng.nextInt(40) + 80).toDouble();
        var st = GameState(s0: s0, s1: s0, h1: null, h2: null);
        st.turn = _rng.nextBool() ? 0 : 1; // 선공 랜덤

        // Linear CFR 가중치 (반복 횟수 비례)
        int currentIter = i + j + 1;

        // 양쪽 플레이어 관점에서 모두 학습 (epsilon 전달)
        cfr(st, 0, 1.0, 1.0, currentIter, epsilon);
        cfr(st, 1, 1.0, 1.0, currentIter, epsilon);
      }

      // 로그 출력 및 진행률 업데이트 (2000회마다)
      int currentTotal = i + 100;
      if (currentTotal % 2000 == 0) {
        double avg = computeAverageRegret();
        double maxR = computeMaxRegret();
        double nashGap = avg / currentTotal;

        debugPrint(
          "Iter $currentTotal | Nodes: ${nodes.length} | "
          "Eps: ${epsilon.toStringAsFixed(4)} | "
          "NashGap: ${nashGap.toStringAsFixed(6)} | "
          "MaxGap: ${(maxR / currentTotal).toStringAsFixed(5)}",
        );
      }

      if (onProgress != null) onProgress(currentTotal / iters);

      // UI 블로킹 방지
      await Future.delayed(Duration.zero);
    }
    debugPrint("🎓 Training Complete! Total Nodes: ${nodes.length}");
  }

  /// CFR 재귀 함수
  /// [epsilon]: 현재 학습 단계의 탐색 상수
  double cfr(
    GameState st,
    int p,
    double pi,
    double piOpp,
    int iter,
    double epsilon,
  ) {
    if (st.done) return st.payoff(p);

    List<Act> valid = st.validActs();
    if (valid.isEmpty) return 0.0;

    // --- InfoSet Key 생성 (상황 인식) ---
    // 1. 히스토리 압축
    String seqStr = _getCompressedHistory(st.history);

    // 2. 상대 카드 랭크 (내 눈에 보이는 정보)
    int oppRank = st.hands[1 - st.turn].rank;

    // 3. 팟 정보 및 SPR (Stack-to-Pot Ratio)
    double pot = st.bets[0] + st.bets[1] + st.pot;
    if (pot < 0.1) pot = 2.0;

    double effectiveStack = min(st.stacks[0], st.stacks[1]);
    double spr = effectiveStack / pot;
    int sprCat = spr < 3 ? 0 : (spr < 8 ? 1 : 2);

    // 4. 상대 베팅 크기 비율 (Bet Size Category)
    double facing = st.bets[1 - st.turn];
    double toCall = facing - st.bets[st.turn];
    int betCat = 0;
    if (toCall > 0) {
      double ratio = toCall / pot;
      betCat = _getBetSizeCategory(ratio);
    }

    // 5. [수정됨] 주도권(Initiative) 확인 로직
    // GameState의 lastAggressor를 확인하여 내가 공격자인지 방어자인지 판단
    int me = st.turn;
    String initiative = "Eq"; // Default: 동등/없음

    if (st.lastAggressor == -1) {
      initiative = "Eq"; // 아무도 베팅 안 함 (Check-Check 상황 등)
    } else if (st.lastAggressor == me) {
      // 내 턴인데 내가 마지막 공격자다? (드문 케이스지만 공격권 보유 의미)
      initiative = "Atk";
    } else {
      // 상대가 마지막으로 공격함 -> 나는 방어해야 함
      initiative = "Def";
    }

    // 최종 Key 생성
    String key =
        "Opp:$oppRank|SPR:$sprCat|Bet:$betCat|Init:$initiative|Hist:$seqStr";
    Node node = getNode(key);
    // ------------------------------------

    // [수정됨] epsilon을 사용하여 현재 전략 가져오기
    List<double> strat = node.getStrat(epsilon);

    List<double> probs = List.filled(ACTION_COUNT, 0.0);
    double sumProb = 0.0;
    for (var act in valid) {
      probs[act.index] = strat[act.index];
      sumProb += strat[act.index];
    }

    // 확률 정규화
    if (sumProb > 0) {
      for (var act in valid) probs[act.index] /= sumProb;
    } else {
      double uniform = 1.0 / valid.length;
      for (var act in valid) probs[act.index] = uniform;
    }

    // 1. 상대 턴 (Opponent Turn)
    if (st.turn != p) {
      double util = 0.0;
      for (var act in valid) {
        // 가지치기 (확률이 매우 낮으면 스킵)
        if (probs[act.index] < 0.001) continue;

        var next = st.clone()..apply(act);
        // 재귀 호출 (epsilon 전달)
        util +=
            probs[act.index] *
            cfr(next, p, pi, piOpp * probs[act.index], iter, epsilon);
      }
      return util;
    }
    // 2. 내 턴 (My Turn)
    else {
      List<double> util = List.filled(ACTION_COUNT, 0.0);
      double nodeUtil = 0.0;

      for (var act in valid) {
        if (probs[act.index] == 0.0) continue;

        var next = st.clone()..apply(act);
        // 재귀 호출 (epsilon 전달)
        util[act.index] = cfr(
          next,
          p,
          pi * probs[act.index],
          piOpp,
          iter,
          epsilon,
        );
        nodeUtil += probs[act.index] * util[act.index];
      }

      // Regret & Strategy Update
      for (var act in valid) {
        double regret = util[act.index] - nodeUtil;

        // Regret 누적 (CFR+)
        node.r[act.index] = max(node.r[act.index] + regret * piOpp, 0.0);

        // Linear CFR: 반복 횟수(iter)를 가중치로 곱해 최신 전략 중요도 UP
        node.s[act.index] += (pi * probs[act.index]) * iter;
      }

      return nodeUtil;
    }
  }
}

// --- Helper Functions ---

/// 히스토리 압축 (최근 3개 액션만 유지)
String _getCompressedHistory(List<dynamic> history) {
  if (history.isEmpty) return '';
  List<dynamic> recent = history.length > 3
      ? history.sublist(history.length - 3)
      : history;
  return '${history.length}_${recent.map((e) => e.index).join('')}';
}

/// 베팅 크기 범주화
int _getBetSizeCategory(double ratio) {
  if (ratio <= 0.05) return 0; // 거의 체크
  if (ratio < 0.4) return 1; // 소액
  if (ratio < 0.9) return 2; // 중간
  return 3; // 팟벳 이상
}
