import 'package:flutter/material.dart';
import '../providers/game_provider.dart';
import 'package:confetti/confetti.dart';
import '../models/card.dart';
import 'widgets/game_controls.dart';
import 'package:provider/provider.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ConfettiController _confettiController;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    // 게임 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().initGame();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Provider 구독
    final provider = context.watch<GameProvider>();

    // 폭죽 트리거 감지
    if (provider.triggerConfetti) {
      _confettiController.play();
    }

    // 로그 자동 스크롤
    if (provider.logs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 배경색
      body: Stack(
        children: [
          Column(
            children: [
              // 1. 상단 헤더 (칩 정보)
              _buildHeader(provider),

              // 2. 게임 테이블 (카드, 팟, AI 말풍선)
              Expanded(child: _buildTable(provider)),

              // 3. 로그 창
              _buildLogView(provider),

              // 4. 컨트롤 패널
              const GameControls(),
            ],
          ),

          // 폭죽 효과 (화면 중앙 상단)
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 위젯 빌더 ---

  Widget _buildHeader(GameProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF263238),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildScore("🤖 AI", provider.chips[0]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(20),
                color: Colors.black54,
              ),
              child: Text(
                "Deck: ${provider.gameState?.hands.isEmpty ?? true ? 20 : 20 - provider.round * 2}", // 근사치
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
            _buildScore("👤 Me", provider.chips[1]),
          ],
        ),
      ),
    );
  }

  Widget _buildScore(String label, double score) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          score.toInt().toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  // lib/ui/game_screen.dart

  Widget _buildTable(GameProvider provider) {
    final gameState = provider.gameState;

    if (gameState == null) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF1b5e20),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [Colors.green.shade800, const Color(0xFF1b5e20)],
          radius: 1.3,
          center: Alignment.center,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 팟 (상단 고정)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(child: _buildPot(provider)),
          ),

          // 2. 메인 게임 영역 (중앙)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // [왼쪽: AI 영역]
                  // 높이 200짜리 고정된 상자를 만듭니다.
                  SizedBox(
                    width: 120, // 너비 고정
                    height: 220, // 높이 고정 (충분히 확보)
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // A. 말풍선 (위쪽에 둥둥 떠있음)
                        Positioned(top: 0, child: _buildAIBrain(provider)),

                        // B. AI 카드 (바닥에 딱 붙어있음) -> 절대 안 움직임!
                        Positioned(
                          bottom: 0,
                          child: _buildPlayerArea(
                            "AI",
                            gameState.hands[0],
                            gameState.bets[0],
                            true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // [중앙: VS]
                  const SizedBox(
                    width: 60,
                    child: Center(
                      child: Text(
                        "VS",
                        style: TextStyle(
                          color: Colors.white12,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),

                  // [오른쪽: Me 영역]
                  // 대칭을 위해 똑같이 높이 220짜리 상자를 씁니다.
                  SizedBox(
                    width: 120,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 내 쪽은 말풍선 없으므로 비워둠

                        // 내 카드 (역시 바닥에 딱 붙임)
                        Positioned(
                          bottom: 0,
                          child: _buildPlayerArea(
                            "You",
                            gameState.hands[1],
                            gameState.bets[1],
                            gameState.done,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIBrain(GameProvider provider) {
    // 내용이 없으면 공간 차지 안 함 (Stack으로 띄울 거라서 괜찮음)
    if (!provider.isThinking && !provider.gameState!.done) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        // 크기 줄임
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16), // 더 둥글게
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 감정 상태 (작게)
            Text(
              provider.aiMoodText,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber,
                fontSize: 11, // 폰트 축소
              ),
            ),
            const SizedBox(height: 2),
            // 생각 텍스트 (작게)
            Text(
              provider.aiThoughtText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.black87,
              ), // 폰트 축소
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 특수 상태 배지
            if (provider.showHeroCall)
              const Text(
                "👁️ Hero Call",
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                ),
              ),
            if (provider.showRisk)
              const Text(
                "⚠️ Risk",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerArea(
    String label,
    GameCard card,
    double bet,
    bool isVisible,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 최소 크기
      children: [
        // 텍스트 영역에 고정 높이(SizedBox)를 주거나,
        // 텍스트 스타일에서 높이를 고정해야 덜컹거리지 않음
        SizedBox(
          height: 24, // 텍스트 공간 고정
          child: Text(
            "$label (Bet: ${bet.toInt()})",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        const SizedBox(height: 6), // 카드와 텍스트 사이 간격
        _buildCard(card, isVisible),
      ],
    );
  }

  Widget _buildCard(GameCard card, bool isVisible) {
    // 1. 카드 뒷면 (패턴 적용)
    if (!isVisible) {
      return Container(
        width: 75,
        height: 110,
        // 둥근 모서리를 위해 ClipRRect 사용
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: CardBackPainter(), // 위에서 만든 페인터 적용
          ),
        ),
      );
    }

    // 2. 카드 앞면
    return Container(
      width: 75,
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE), // --card-bg
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          "${card.rank}",
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            // 하트, 다이아는 빨간색, 나머지는 검은색
            color: card.isRed
                ? const Color(0xFFC62828)
                : const Color(0xFF212121),
          ),
        ),
      ),
    );
  }

  Widget _buildPot(GameProvider provider) {
    // 1. 이월 상태 확인 (현재 판이 이월된 판이거나, 방금 비겨서 다음 판으로 넘어갈 돈이 있거나)
    bool isCarried =
        (provider.gameState?.wasCarried ?? false) || provider.carriedPot > 0;

    // 2. 표시할 금액
    double currentPot = provider.gameState?.pot ?? 0;

    // 라운드가 끝났고(무승부 상황) 이월된 팟이 있다면 그 금액을 보여줌
    if (provider.gameState != null &&
        provider.gameState!.done &&
        provider.carriedPot > 0) {
      currentPot = provider.carriedPot;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF263238), // 배경은 항상 진한 색 (가독성 위해)
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          // 이월이면 진한 황금색, 평소엔 연한 색
          color: isCarried ? const Color(0xFFFFD700) : Colors.amber.shade200,
          width: isCarried ? 3 : 1.5, // 이월되면 테두리 두껍게
        ),
        boxShadow: isCarried
            ? [
                // 이월 시: 황금빛 광채 (Glow Effect)
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.6),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : [
                // 평소: 은은한 그림자
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // [이월 뱃지] 이월 상태일 때만 자물쇠와 텍스트 표시
          if (isCarried)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.lock,
                    color: Color(0xFFFFD700),
                    size: 12,
                  ), // 황금 자물쇠
                  SizedBox(width: 4),
                  Text(
                    "CARRY OVER",
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),

          // [팟 금액]
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "POT: ",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "${currentPot.toInt()}",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  // 이월이면 쨍한 황금색, 아니면 일반 호박색
                  color: isCarried ? const Color(0xFFFFD700) : Colors.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogView(GameProvider provider) {
    return Container(
      height: 100,
      color: Colors.black,
      child: ListView.builder(
        controller: _logScrollController,
        padding: const EdgeInsets.all(8),
        itemCount: provider.logs.length,
        itemBuilder: (context, index) {
          String log = provider.logs[index];
          Color color = Colors.grey;
          if (log.contains("AI:")) color = Colors.amber;
          if (log.contains("You:")) color = Colors.blue;
          if (log.contains("WIN")) color = Colors.greenAccent;
          if (log.contains("LOSE")) color = Colors.redAccent;
          if (log.contains("!!")) color = Colors.red;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(log, style: TextStyle(color: color, fontSize: 12)),
          );
        },
      ),
    );
  }
}

// lib/ui/game_screen.dart 맨 아래에 추가

class CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 배경색 (CSS: #455a64)
    final paintBg = Paint()..color = const Color(0xFF455A64);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintBg);

    // 줄무늬 색 (CSS: #37474f)
    final paintLine = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4; // 줄 두께

    // 빗살무늬 그리기
    for (double i = -size.height; i < size.width; i += 10) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paintLine,
      );
    }

    // 테두리
    final borderPaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
