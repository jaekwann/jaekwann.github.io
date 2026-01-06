// lib/models/deck.dart
import 'dart:math';
import '../utils/constants.dart'; // ranks, maxDeckSize 불러오기
import 'card.dart';

class Deck {
  List<GameCard> cards = [];
  final int _max = maxDeckSize;

  // 덱 초기화 및 셔플 (JS: init)
  void init() {
    cards.clear();
    // 2세트 생성 (스페이드=s, 하트=h 로 가정)
    // i=0 -> s (black), i=1 -> h (red)
    for (int i = 0; i < 2; i++) {
      for (int r in ranks) {
        cards.add(GameCard(rank: r, suit: i == 0 ? 's' : 'h'));
      }
    }
    cards.shuffle(Random());
    print("🔄 Deck Reshuffled: ${cards.length}/$_max");
  }

  // 카드 뽑기 (JS: draw)
  GameCard draw() {
    if (cards.length < 2) {
      init();
    }
    return cards.removeLast();
  }

  int get remaining => cards.length;
}
