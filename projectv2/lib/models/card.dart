// lib/models/card.dart

class GameCard {
  final int rank; // 1 ~ 10
  final String suit; // 's' (Spade) or 'h' (Heart) - 단순화됨
  bool isHidden; // 카드가 뒷면인지 여부

  GameCard({required this.rank, required this.suit, this.isHidden = false});

  // 카드가 빨간색(하트/다이아) 계열인지 확인 (UI용)
  bool get isRed => suit == 'h' || suit == 'd';

  @override
  String toString() => '[$rank$suit]';

  // 깊은 복사를 위한 팩토리 메서드
  factory GameCard.clone(GameCard other) {
    return GameCard(
      rank: other.rank,
      suit: other.suit,
      isHidden: other.isHidden,
    );
  }
}
