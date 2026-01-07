import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../utils/constants.dart';

class GameControls extends StatefulWidget {
  const GameControls({Key? key}) : super(key: key);

  @override
  State<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<GameControls> {
  double _sliderValue = 0.0;
  bool _isInit = false; // 슬라이더 초기값 설정을 위한 플래그

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final gameState = provider.gameState;

    // 1. 내 턴인지 확인
    bool isMyTurn = gameState != null && !gameState.done && gameState.turn == 1;
    List<Act> validActs = isMyTurn ? gameState.validActs() : [];

    // 2. 슬라이더 범위 계산 (절대값 기준)
    double minBet = 0.0;
    double maxBet = 0.0;
    bool canUseSlider = false;

    if (isMyTurn) {
      double myStack = gameState.stacks[1]; // 내 남은 칩
      double oppBet = gameState.bets[0]; // 상대방이 건 돈
      double myBet = gameState.bets[1]; // 내가 이미 건 돈 (보통 0 혹은 앤티)
      double diff = oppBet - myBet; // 콜(Call) 하기 위해 필요한 차액

      // [규칙] 최소 레이즈 금액 = (상대방 베팅액) + (직전 레이즈 규모 or 1)
      // 즉, 상대를 이기려면 최소한 '콜 금액 + 알파'를 내야 함
      double minRaiseAmt = diff > 0 ? (oppBet + diff) : 1.0;
      // 만약 상대가 10 걸었으면, 나는 20(콜10+레이즈10)부터 레이즈 가능

      // 실제 슬라이더 최소값: 내 스택 안에서 낼 수 있어야 함
      // (단, 체크/콜 상황보다 더 많이 걸 때만 슬라이더 의미가 있음)
      // double effectiveMin = diff > 0 ? (diff + 1) : 1.0; // 최소한 1칩은 더 걸어야 함

      // 포커 룰상 minRaiseAmt를 지키는 게 맞지만,
      // 앱 편의상 '내 스택'이 허용하는 한 1칩 단위로 자유롭게 (단, 콜 금액보다는 커야 함)
      minBet = minRaiseAmt;

      // 내가 가진 돈이 최소 레이즈 금액보다 적으면 슬라이더 못 씀 (올인 버튼 써야 함)
      if (myStack > minBet) {
        canUseSlider = true;
        maxBet = myStack;

        // 슬라이더 초기값이 범위 밖이면 최소값으로 보정
        if (!_isInit || _sliderValue < minBet || _sliderValue > maxBet) {
          _sliderValue = minBet;
          _isInit = true;
        }
      }
    } else {
      _isInit = false; // 턴이 끝나면 초기화 플래그 리셋
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // === 1. 슬라이더 영역 (절대값) ===
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFFffd700), // 골드
                    inactiveTrackColor: Colors.grey[800],
                    thumbColor: const Color(0xFFffd700),
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: canUseSlider ? _sliderValue : 0,
                    min: canUseSlider ? minBet : 0,
                    max: canUseSlider ? maxBet : 100,
                    divisions: (canUseSlider && maxBet > minBet)
                        ? (maxBet - minBet).toInt()
                        : 1, // 1단위 이동
                    label: canUseSlider ? _sliderValue.toInt().toString() : "",
                    onChanged: canUseSlider
                        ? (val) {
                            setState(() {
                              _sliderValue = val;
                            });
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 베팅 버튼 (슬라이더 값 적용)
              SizedBox(
                width: 80,
                height: 40,
                child: ElevatedButton(
                  onPressed: canUseSlider && isMyTurn
                      ? () {
                          provider.playerBetCustom(_sliderValue);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFffd700),
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    canUseSlider ? "Bet ${_sliderValue.toInt()}" : "Bet",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // === 2. 액션 버튼 그리드 ===
          Row(
            children: [
              // Fold
              _buildBtn(
                "Fold",
                Colors.red[800]!,
                isMyTurn && validActs.contains(Act.fold)
                    ? () => provider.playerAct(Act.fold)
                    : null,
              ),
              const SizedBox(width: 8),

              // Check / Call
              _buildBtn(
                isMyTurn && (gameState!.bets[0] > gameState.bets[1])
                    ? "Call"
                    : "Check",
                Colors.green[700]!,
                isMyTurn && (validActs.contains(Act.check))
                    ? () => provider.playerAct(Act.check)
                    : null,
              ),
              const SizedBox(width: 8),

              // 50% (Half Bet)
              _buildBtn(
                "50%",
                const Color(0xFF1565C0),
                isMyTurn && validActs.contains(Act.betHalf)
                    ? () => provider.playerAct(Act.betHalf)
                    : null,
              ),
              const SizedBox(width: 8),

              // Pot (Full Pot Bet)
              _buildBtn(
                "Pot",
                const Color(0xFF0D47A1),
                isMyTurn && validActs.contains(Act.betPot)
                    ? () => provider.playerAct(Act.betPot)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // All-In 버튼 (가로 꽉 채움)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: isMyTurn && validActs.contains(Act.allIn)
                  ? () => provider.playerAct(Act.allIn)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "ALL IN",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn(String text, Color color, VoidCallback? onTap) {
    return Expanded(
      child: SizedBox(
        height: 48, // 버튼 높이 통일
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white30,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 2,
          ),
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
