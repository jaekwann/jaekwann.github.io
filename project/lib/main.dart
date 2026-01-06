import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/game_provider.dart';
import 'ui/game_screen.dart';

void main() {
  // 플러터 엔진 초기화 보장 (SystemChrome 등 사용 시 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // 화면을 세로 모드로 고정 (게임 레이아웃 깨짐 방지)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 상태 표시줄(배터리, 시간 등) 스타일 설정
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // 투명하게
    statusBarIconBrightness: Brightness.light, // 아이콘은 흰색
  ));

  runApp(
    // 앱 최상단에 Provider 주입
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Tazza AI: Indian Hold'em", // 앱 이름
      debugShowCheckedModeBanner: false, // 우측 상단 'Debug' 띠 제거
      
      // 다크 테마 적용
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212), // 배경색 (CSS와 동일)
        primaryColor: const Color(0xFF1b5e20), // 메인 녹색
        
        // 버튼 등 강조 색상 설정
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFffd700), // 골드 (Accent Color)
          secondary: Color(0xFF1565c0), // 버튼 블루
          surface: Color(0xFF1E1E1E), // 카드/패널 배경
        ),
        
        // 슬라이더 스타일 전역 설정
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFFffd700),
          thumbColor: const Color(0xFFffd700),
          inactiveTrackColor: Colors.grey[800],
        ),
      ),
      
      // 앱 시작 화면
      home: const GameScreen(),
    );
  }
}