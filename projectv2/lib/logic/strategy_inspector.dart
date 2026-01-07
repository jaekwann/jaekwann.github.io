import 'package:flutter/foundation.dart';
import 'solver.dart';
import '../utils/constants.dart';

class StrategyInspector {
  final Solver solver;

  StrategyInspector(this.solver);

  void printKeyStrategies() {
    debugPrint("\n============== 🔬 AI 초정밀 전략 검사 ==============");
    debugPrint("📊 변경된 스펙: Bet(12단계), Odds(5%단위), Hist(5길이)\n");

    // 검사할 3가지 시나리오의 통계 수집
    _analyzeScenario(
      title: "1️⃣ [절체절명] 상대 10 & 팟 베팅 이상",
      targetOpp: 10,
      targetBets: [7, 8, 9, 10, 11], // Pot(7) ~ All-in(11)
      passCondition: (fold, call, bet) => fold >= 90.0,
      successMsg: "✅ 합격: 10 상대로 팟 베팅 맞으면 90% 이상 도망감",
      failMsg: "❌ 불합격: 무모하게 덤빔 (Fold 낮음)",
    );

    _analyzeScenario(
      title: "2️⃣ [호구 사냥] 상대 1 & 체크",
      targetOpp: 1,
      targetBets: [0], // Check(0)
      passCondition: (fold, call, bet) => bet >= 80.0,
      successMsg: "✅ 합격: 1 상대로 체크하면 80% 이상 공격함",
      failMsg: "❌ 불합격: 너무 소극적임 (Bet 낮음)",
    );

    _analyzeScenario(
      title: "3️⃣ [눈치 싸움] 상대 5 & 체크",
      targetOpp: 5,
      targetBets: [0], // Check(0)
      passCondition: (fold, call, bet) => call > 10.0 && bet > 10.0,
      successMsg: "✅ 합격: Check와 Bet을 적절히 섞어서 플레이 (Mixed Strategy)",
      failMsg: "❌ 불합격: 전략이 한쪽으로 쏠림 (단조로움)",
    );

    debugPrint("======================================================");
  }

  /// 여러 노드를 검색해서 평균 전략을 계산하는 함수
  void _analyzeScenario({
    required String title,
    required int targetOpp,
    required List<int> targetBets,
    required bool Function(double, double, double) passCondition,
    required String successMsg,
    required String failMsg,
  }) {
    double totalFold = 0;
    double totalCall = 0;
    double totalBet = 0;
    int count = 0;

    // 모든 노드를 뒤져서 조건에 맞는 상황의 평균을 냄
    for (var entry in solver.nodes.entries) {
      String key = entry.key;
      // 키 파싱 없이 문자열 포함 여부로 빠르게 필터링
      if (!key.contains("Opp:$targetOpp|")) continue;

      bool betMatched = false;
      for (int b in targetBets) {
        if (key.contains("Bet:$b|")) {
          betMatched = true;
          break;
        }
      }
      if (!betMatched) continue;

      // 찾았다! 해당 노드의 전략 합산
      List<double> strat = entry.value.getAvgStrat();
      totalFold += strat[Act.fold.index];
      totalCall += strat[Act.check.index];
      totalBet +=
          (strat[Act.betHalf.index] +
          strat[Act.betPot.index] +
          strat[Act.allIn.index]);
      count++;
    }

    debugPrint("\n$title");
    if (count == 0) {
      debugPrint("⚠️ 데이터 부족: 해당 상황에 도달하지 못함 (학습량 부족 가능성)");
      return;
    }

    // 평균 계산
    double avgFold = (totalFold / count) * 100;
    double avgCall = (totalCall / count) * 100;
    double avgBet = (totalBet / count) * 100;

    debugPrint("🔍 검색된 상황 수: $count개 (평균값)");
    debugPrint(
      "📊 전략: 🏳️Fold:${avgFold.toStringAsFixed(1)}% | ✋Check:${avgCall.toStringAsFixed(1)}% | ⚔️Bet:${avgBet.toStringAsFixed(1)}%",
    );

    if (passCondition(avgFold, avgCall, avgBet)) {
      debugPrint(successMsg);
    } else {
      debugPrint(failMsg);
    }
  }
}
