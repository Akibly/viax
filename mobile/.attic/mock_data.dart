import 'design/components/concept_graph.dart';
import 'design/components/rubric_ring.dart';
import 'design/tokens.dart';

/// Sample data for running the UI without a backend.
///
/// These are illustrative figures for one fictional student, not a real
/// record — the app says so on screen. They exist so the interface can be
/// operated and reviewed while the API is still being built; every provider
/// that currently reads from here gets swapped for a repository call without
/// the widgets changing.
abstract final class Mock {
  static final examDate = DateTime.now().add(const Duration(days: 3));

  static const readiness = 62.0;
  static const confidence = 74.0;
  static const coverage = 81.0;

  static const prediction =
      'Two critical gaps hold this down. Clearing Mutual Exclusion alone '
      'releases four dependent concepts.';

  /// The prerequisite structure is the point: Monitor, Semaphore and Deadlock
  /// all trace back to Mutual Exclusion, so the ranked list alone would send
  /// a student to revise the wrong thing.
  static const concepts = <VxConcept>[
    VxConcept(
      id: 'mon',
      name: 'Monitor',
      mastery: 22,
      delta: -4,
      blockedBy: 'Mutual Exclusion',
      dueLabel: 'Due today',
    ),
    VxConcept(
      id: 'bank',
      name: "Banker's Algorithm",
      mastery: 26,
      delta: -2,
      blockedBy: 'Deadlock',
      dueLabel: 'Due today',
    ),
    VxConcept(
      id: 'sem',
      name: 'Semaphore',
      mastery: 29,
      delta: 3,
      blockedBy: 'Mutual Exclusion',
      dueLabel: 'Due tomorrow',
    ),
    VxConcept(
      id: 'mutex',
      name: 'Mutual Exclusion',
      mastery: 31,
      delta: -6,
      dueLabel: 'Due today',
    ),
    VxConcept(
      id: 'dead',
      name: 'Deadlock',
      mastery: 34,
      delta: -6,
      blockedBy: 'Mutual Exclusion',
      dueLabel: 'Due today',
    ),
    VxConcept(id: 'vm', name: 'Virtual Memory', mastery: 41, delta: 7, dueLabel: 'Due tomorrow'),
    VxConcept(id: 'tlb', name: 'TLB', mastery: 47, delta: 2, dueLabel: 'Due Saturday'),
    VxConcept(id: 'page', name: 'Paging', mastery: 58, delta: 3, dueLabel: 'Due Saturday'),
    VxConcept(id: 'sync', name: 'Synchronization', mastery: 76, delta: 11, dueLabel: 'Due in 6 days'),
    VxConcept(id: 'sched', name: 'Scheduling', mastery: 82, delta: 0, dueLabel: 'Due in 9 days'),
    VxConcept(id: 'fs', name: 'File Systems', mastery: 0, untested: true),
    VxConcept(id: 'inode', name: 'Inode', mastery: 0, untested: true),
  ];

  static const question =
      'A system has four processes and three identical resource units. What '
      'is the maximum each process may request while the system still cannot '
      'deadlock — and why?';

  /// Three real student responses at different depths. Selecting one shows
  /// how the rubric separates "knows the fact" from "can defend it".
  static const answers = <MockAnswer>[
    MockAnswer(
      label: 'Surface',
      text: 'Deadlock happens when processes wait for each other in a circle, '
          'so you have to avoid circular waiting.',
      score: 34,
      verdict: 'Names the condition, misses the question',
      note: 'You recalled circular wait — one of four Coffman conditions — but '
          'the question asked for a bound on requests, and no number appears '
          'in your answer. An examiner would stop you here and ask for it.',
      rubric: [
        ('Concept Accuracy', 55.0),
        ('Completeness', 20.0),
        ('Technical Vocabulary', 45.0),
        ('Logical Flow', 40.0),
        ('Depth', 15.0),
        ('Examples Used', 10.0),
      ],
      gapTitle: 'The counting argument',
      gapBody: 'There is a quantitative bound here. With three units shared by '
          'four processes, the pigeonhole argument fixes what each may hold.',
    ),
    MockAnswer(
      label: 'Partial',
      text: 'With three units and four processes, if each holds one there is '
          'nothing left, so at most one unit each — otherwise you can get a '
          'circular wait.',
      score: 58,
      verdict: 'Right answer, unproven',
      note: 'You reached the bound and gestured at why. What is missing is the '
          'general form: the system is safe when total units exceed the sum of '
          'maximum needs minus the number of processes.',
      rubric: [
        ('Concept Accuracy', 70.0),
        ('Completeness', 45.0),
        ('Technical Vocabulary', 60.0),
        ('Logical Flow', 65.0),
        ('Depth', 40.0),
        ('Examples Used', 30.0),
      ],
      gapTitle: 'The general safety condition',
      gapBody: 'Your reasoning works for these numbers but does not '
          'generalise. The follow-up — five processes, seven units — would '
          'not be answerable from what you said.',
    ),
    MockAnswer(
      label: 'Complete',
      text: 'Each may request at most one unit. Deadlock needs every process '
          'holding at least one while waiting for another; with three units '
          'the fourth process always finds one free. Generally the system is '
          'safe when total units exceed the sum of maximum needs minus the '
          'process count.',
      score: 87,
      verdict: 'Bound, mechanism, and generalisation',
      note: 'You gave the bound, the mechanism that produces it, and the '
          'general condition it is an instance of. This is what a '
          'distinction-grade viva answer sounds like.',
      rubric: [
        ('Concept Accuracy', 92.0),
        ('Completeness', 88.0),
        ('Technical Vocabulary', 85.0),
        ('Logical Flow', 90.0),
        ('Depth', 82.0),
        ('Examples Used', 70.0),
      ],
      gapTitle: null,
      gapBody: null,
    ),
  ];

  /// The revision queue.
  ///
  /// Dates, not buckets. The original schema stored this as an enum
  /// (today / tomorrow / weekend / before_exam) with no date attached, so
  /// "today" was wrong by tomorrow and nothing could roll over (audit DB-04).
  /// These carry a real due date and an FSRS interval; the tabs are views
  /// over that date, not stored categories.
  static final revision = <RevisionItem>[
    RevisionItem('Mutual exclusion — the four conditions', 15, 0, 1, true),
    RevisionItem('Deadlock — necessary vs sufficient', 15, 0, 1, false),
    RevisionItem('Semaphore vs monitor', 12, 0, 2, false),
    RevisionItem('Virtual memory basics', 10, 1, 4, false),
    RevisionItem('Paging vs segmentation', 20, 1, 4, false),
    RevisionItem('Page replacement — LRU and clock', 18, 3, 7, false),
    RevisionItem('Synchronization primitives', 15, 3, 12, false),
    RevisionItem('Full mock viva · professor mode', 35, 8, 21, false),
  ];

  static const passage =
      'If the total number of resource units exceeds the sum of the maximum '
      'needs of all processes minus the number of processes, the system is '
      'deadlock-free by construction.';
}

class MockAnswer {
  const MockAnswer({
    required this.label,
    required this.text,
    required this.score,
    required this.verdict,
    required this.note,
    required this.rubric,
    required this.gapTitle,
    required this.gapBody,
  });

  final String label;
  final String text;
  final double score;
  final String verdict;
  final String note;
  final List<(String, double)> rubric;
  final String? gapTitle;
  final String? gapBody;

  /// Confidence is never among these. It is prosodic — carried by pace and
  /// hesitation, not word choice — so a typed answer cannot supply it.
  List<VxDimension> get dimensions => [
        for (final (name, value) in rubric)
          VxDimension(name: name, score: value),
        const VxDimension(
          name: 'Confidence',
          score: 0,
          unavailableReason: 'Requires voice',
        ),
      ];

  VxMode get mode => VxMode.examination;
}


/// One scheduled revision task.
class RevisionItem {
  RevisionItem(this.title, this.minutes, this.dueInDays, this.intervalDays,
      this.done);

  final String title;
  final int minutes;

  /// Days from today. 0 is due now.
  final int dueInDays;

  /// The FSRS interval this card earned at its last review — the number that
  /// makes the schedule inspectable rather than magic.
  final int intervalDays;

  bool done;

  String get dueLabel => switch (dueInDays) {
        <= 0 => 'Today',
        1 => 'Tomorrow',
        < 7 => 'This week',
        _ => 'Before the viva',
      };
}
