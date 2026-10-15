import 'package:flutter/foundation.dart';

import '../../data/repository.dart';

/// A flashcard / study item.
@immutable
class StudyCard {
  const StudyCard({
    required this.id,
    required this.term,
    required this.definition,
    this.starred = false,
    this.masteryLevel = 0, // 0 = New, 1 = Learning, 2 = Mastered
  });

  final String id;
  final String term;
  final String definition;
  final bool starred;
  final int masteryLevel;

  StudyCard copyWith({
    String? id,
    String? term,
    String? definition,
    bool? starred,
    int? masteryLevel,
  }) {
    return StudyCard(
      id: id ?? this.id,
      term: term ?? this.term,
      definition: definition ?? this.definition,
      starred: starred ?? this.starred,
      masteryLevel: masteryLevel ?? this.masteryLevel,
    );
  }

  /// Converts a ConceptRow or concept into a StudyCard
  factory StudyCard.fromConcept(ConceptRow concept) {
    return StudyCard(
      id: concept.id,
      term: concept.name,
      // Callers only build cards for concepts with a grounded description.
      // Inventing a generic sentence here made empty data look complete and
      // trained students on material that never appeared in their notes.
      definition: concept.description!.trim(),
      masteryLevel: (concept.mastery ?? 0) >= 75
          ? 2
          : (concept.mastery ?? 0) >= 40
              ? 1
              : 0,
    );
  }
}
