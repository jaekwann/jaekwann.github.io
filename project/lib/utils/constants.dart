// lib/utils/constants.dart

/// 카드 숫자 (1 ~ 10)
const List<int> ranks = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/// 행동 타입 정의 (JS의 ACT 객체를 Enum으로 변환)
/// FOLD:0, CHECK:1, BET_H:2, BET_P:3, BET_O:4, ALLIN:5
enum Act {
  fold, // 0
  check, // 1 (Check or Call)
  betHalf, // 2
  betPot, // 3
  overBet, // 4 (JS의 BET_O)
  allIn, // 5
}

/// 행동별 버튼/로그 텍스트 매핑 (JS의 ACT_TXT)
const Map<Act, String> actText = {
  Act.fold: "Fold",
  Act.check: "Check/Call",
  Act.betHalf: "Bet Half",
  Act.betPot: "Bet Pot",
  Act.overBet: "Overbet",
  Act.allIn: "All-In",
};

/// 베팅 배율 설정 (JS의 MULTS)
/// 하프(0.5), 팟(1.0), 오버벳(1.5), 올인(999 - 무제한 의미)
const Map<Act, double> betMults = {
  Act.betHalf: 0.5,
  Act.betPot: 1.0,
  Act.overBet: 1.5,
  Act.allIn: 999.0, // 사실상 무한대(전부)
};

/// 초기 칩 설정 (JS의 chips = [100, 100])
const double initialChips = 100.0;

/// 덱 설정 (JS의 shoe.max)
const int maxDeckSize = 20;

/// AI 학습 반복 횟수 (JS의 50000)
/// Flutter에서 Isolate 없이 돌릴 땐 렉이 걸릴 수 있으므로
/// 테스트할 땐 100~500 정도로 낮추고, 나중에 최적화할 예정.
const int trainingIterations = 10000;
