import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/screens/study/study_models.dart';
import 'package:vivax/data/repository.dart';

void main() {
  group('Grounded study models', () {
    test('StudyCard.fromConcept correctly maps ConceptRow', () {
      const concept = ConceptRow(
        id: 'c1',
        name: 'Backpropagation',
        description: 'The chain-rule method described in the uploaded notes.',
        importance: 3,
        mastery: 85.0,
      );

      final card = StudyCard.fromConcept(concept);
      expect(card.id, 'c1');
      expect(card.term, 'Backpropagation');
      expect(card.definition,
          'The chain-rule method described in the uploaded notes.');
      expect(card.masteryLevel, 2); // 85% >= 75% -> Mastered (2)
    });

    test('StudyCard.copyWith updates specific fields properly', () {
      const card = StudyCard(
        id: 'c1',
        term: 'Deadlock',
        definition: 'A cycle of processes waiting for resources.',
      );
      final updated = card.copyWith(starred: true, masteryLevel: 2);

      expect(updated.id, card.id);
      expect(updated.term, card.term);
      expect(updated.definition, card.definition);
      expect(updated.starred, isTrue);
      expect(updated.masteryLevel, 2);
    });
  });
}
