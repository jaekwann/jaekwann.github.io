// lib/models/user_stats.dart

class UserStats {
  int totalHands = 0;
  int foldCount = 0;
  int bluffOpportunities = 0; // 블러핑이 가능한 상황(쇼다운)
  int bluffsDetected = 0; // 실제 블러핑 감지 횟수

  // 폴드 비율 (0.0 ~ 1.0)
  double getFoldRate() {
    if (totalHands < 1) return 0.0;
    return foldCount / totalHands;
  }

  // 블러핑 감지 비율 (0.0 ~ 1.0)
  double getBluffRate() {
    if (bluffOpportunities < 1) return 0.0;
    return bluffsDetected / bluffOpportunities;
  }

  void reset() {
    totalHands = 0;
    foldCount = 0;
    bluffOpportunities = 0;
    bluffsDetected = 0;
  }
}
