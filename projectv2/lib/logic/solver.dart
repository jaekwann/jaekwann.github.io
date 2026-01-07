// lib/logic/solver.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import '../models/game_state.dart';
import '../models/card.dart';
import 'exploitability.dart';
import '../utils/constants.dart';

final int ACTION_COUNT = Act.values.length;

// Isolate로 보낼 메시지 클래스
class TrainMessage {
  final int iterations;
  final SendPort sendPort;
  TrainMessage(this.iterations, this.sendPort);
}

class Node {
  List<double> r = List.filled(ACTION_COUNT, 0.0);
  List<double> s = List.filled(ACTION_COUNT, 0.0);

  List<double> getStrat() {
    double sum = 0.0;
    List<double> strat = List.filled(ACTION_COUNT, 0.0);
    for (int i = 0; i < ACTION_COUNT; i++) {
      double val = max(r[i], 0.0);
      strat[i] = val;
      sum += val;
    }
    if (sum > 0) {
      for (int i = 0; i < ACTION_COUNT; i++) strat[i] /= sum;
    } else {
      double uniform = 1.0 / ACTION_COUNT;
      for (int i = 0; i < ACTION_COUNT; i++) strat[i] = uniform;
    }
    return strat;
  }

  List<double> getAvgStrat() {
    double sum = s.fold(0.0, (a, b) => a + b);
    List<double> avgStrat = List.filled(ACTION_COUNT, 0.0);
    if (sum > 0) {
      for (int i = 0; i < ACTION_COUNT; i++) avgStrat[i] = s[i] / sum;
    } else {
      // 학습된 적 없으면 균등 분포 반환
      double uniform = 1.0 / ACTION_COUNT;
      for (int i = 0; i < ACTION_COUNT; i++) avgStrat[i] = uniform;
    }
    return avgStrat;
  }
}

class Solver {
  Map<String, Node> nodes = {};
  final Random _rng = Random();

  // 싱글톤 패턴이 아니라면 인스턴스 메서드로 유지
  Node getNode(String key) => nodes.putIfAbsent(key, () => Node());

  // [키 생성 로직]
  // 주의: 학습과 테스트 시 같은 상황이면 반드시 같은 String이 나와야 함
  static String generateKey(GameState st) {
    // 1. 내 관점에서 본 상대 카드 (인디언 포커: 상대 이마의 카드는 보임)
    // st.turn이 '나'라면, 1-st.turn은 상대방
    int oppRank = st.hands[1 - st.turn].rank;

    // 2. 베팅 히스토리 압축
    String seqStr = '';
    if (st.history.isNotEmpty) {
      // 너무 길면 최근 5개만 (메모리 절약)
      List<dynamic> recent = st.history.length > 5
          ? st.history.sublist(st.history.length - 5)
          : st.history;
      seqStr = recent.map((e) => e.index).join('');
    }

    // 3. 상황별 버킷 (정밀도 조정)
    double pot = st.bets[0] + st.bets[1] + st.pot;
    if (pot < 1.0) pot = 2.0; // 방어 코드

    // SPR (Stack to Pot Ratio)
    double effectiveStack = min(st.stacks[0], st.stacks[1]);
    double spr = effectiveStack / pot;
    int sprCat = spr < 2.0 ? 0 : 1; // 1.0 -> 2.0으로 약간 여유 줌

    // 내 차례에 콜해야 할 금액 비율
    double facing = st.bets[1 - st.turn];
    double toCall = facing - st.bets[st.turn];
    int betCat = 0;

    if (toCall > 0) {
      double ratio = toCall / pot;
      if (ratio <= 0.35)
        betCat = 1; // 1/3 팟 이하
      else if (ratio <= 0.80)
        betCat = 2; // 2/3 ~ 3/4 팟
      else if (ratio <= 1.5)
        betCat = 3; // 팟벳 ~ 1.5배
      else
        betCat = 4; // 빅벳
    }

    // 주도권 (Initiative)
    int me = st.turn;
    String initiative = "Eq";
    if (st.lastAggressor != -1) {
      initiative = st.lastAggressor == me ? "Atk" : "Def";
    }

   

    return "Opp:$oppRank|SPR:$sprCat|Bet:$betCat|Init:$initiative|Hist:$seqStr";
  }

  /// [Isolate 실행 함수]
  /// 메인 스레드 멈춤 방지를 위해 별도 실행
  Future<void> runTrainingInBackground(
    int iters,
    Function(String log) onLog,
  ) async {
    final receivePort = ReceivePort();

    // Isolate 생성 및 시작
    await Isolate.spawn(
      _isolateEntry,
      TrainMessage(iters, receivePort.sendPort),
    );

    // 로그 및 결과 수신
    await for (final message in receivePort) {
      if (message is Map<String, Node>) {
        // 학습 완료: 결과를 메인 스레드에 병합
        this.nodes = message;
        onLog("✅ Training Data Merged. Nodes: ${nodes.length}");
        receivePort.close(); // 종료
        break;
      } else if (message is String) {
        // 진행 상황 로그
        onLog(message);
      }
    }
  }

  // Isolate 내부에서 돌아가는 실제 학습 로직
  static void _isolateEntry(TrainMessage msg) {
    // Isolate 내부는 메모리가 격리되어 있으므로 새로운 Solver 인스턴스 생성
    Solver localSolver = Solver();
    int batchSize = 1000; // 계산 빈도

    for (int i = 0; i < msg.iterations; i += batchSize) {
      for (int j = 0; j < batchSize; j++) {
        localSolver._runSingleIteration(i + j);
      }

      // 진행 상황 보고 (메인 스레드로 전송)
      if ((i + batchSize) % 10000 == 0) {
        // 여기서 Exploitability 계산
        var exploitCalc = ExploitabilityCalculator(localSolver, ante: 1.0);
        double exploit = exploitCalc.calculate();

        msg.sendPort.send(
          "[${((i + batchSize) / msg.iterations * 100).toStringAsFixed(0)}%] "
          "Iter: ${i + batchSize} | Exp: ${exploit.toStringAsFixed(4)} | Nodes: ${localSolver.nodes.length}",
        );
      }
    }

    // 최종 결과 전송 (Map 전체를 보냄 - 대량 데이터일 경우 주의 필요)
    msg.sendPort.send(localSolver.nodes);
  }

  // 단일 반복 학습 함수
  void _runSingleIteration(int iter) {
    // 1. 카드 딜링 (중복 방지)
    int r1 = _rng.nextInt(10) + 1;
    int r2;
    do {
      r2 = _rng.nextInt(10) + 1;
    } while (r1 == r2);

    // [중요 수정] 스택을 80.0으로 고정하여 Exploitability 계산기와 환경 일치시킴
    // 학습이 안정화되면 나중에 랜덤으로 변경하세요.
    double s0 = 80.0;

    var st = GameState(
      s0: s0,
      s1: s0,
      h1: GameCard(rank: r1, suit: 's'),
      h2: GameCard(rank: r2, suit: 'h'),
      ante: 1.0,
    );
    st.turn = _rng.nextBool() ? 0 : 1;

    // Linear CFR+ Weight
    double d = max(iter.toDouble(), 1.0);
    

    cfr(st, 1.0, 1.0, d);
  }

  double cfr(GameState st, double p0, double p1, double weight) {
    if (st.done) return st.payoff(0);

    List<Act> valid = st.validActs();
    if (valid.isEmpty) return 0.0;

    String key = Solver.generateKey(st);
    Node node = getNode(key);
    List<double> strategy = node.getStrat();

    // Renormalization (유효하지 않은 행동 확률 제거)
    double probSum = 0.0;
    for (var act in valid) probSum += strategy[act.index];

    if (probSum > 0) {
      for (var act in valid) strategy[act.index] /= probSum;
    } else {
      double uniform = 1.0 / valid.length;
      for (var act in valid) strategy[act.index] = uniform;
    }

    List<double> util = List.filled(ACTION_COUNT, 0.0);
    double nodeUtil = 0.0;

    for (var act in valid) {
      var next = st.clone()..apply(act);
      if (st.turn == 0) {
        util[act.index] = cfr(next, p0 * strategy[act.index], p1, weight);
      } else {
        util[act.index] = cfr(next, p0, p1 * strategy[act.index], weight);
      }
      nodeUtil += strategy[act.index] * util[act.index];
    }

    // Regret & Strategy Update
    if (st.turn == 0) {
      for (var act in valid) {
        double regret = util[act.index] - nodeUtil;
        node.r[act.index] = max(node.r[act.index] + p1 * regret, 0.0);
        // P0의 전략은 P0의 도달 확률(p0) * 가중치(weight)로 누적
        node.s[act.index] += (p0 * weight) * strategy[act.index];
      }
    } else {
      for (var act in valid) {
        double regret = (-util[act.index]) - (-nodeUtil); // P1은 음수 유틸리티가 이득
        node.r[act.index] = max(node.r[act.index] + p0 * regret, 0.0);
        node.s[act.index] += (p1 * weight) * strategy[act.index];
      }
    }

    return nodeUtil;
  }
}
