import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, UserAttributes, FunctionException;

import 'supabase_client.dart';

/// A subject the student is being examined on.
@immutable
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.documentCount,
    required this.conceptCount,
    this.examDate,
    this.groundedConceptIds = const [],
  });

  final String id;
  final String name;
  final int documentCount;
  final int conceptCount;
  final DateTime? examDate;
  final List<String> groundedConceptIds;

  /// Below this a viva would have to invent questions the notes cannot
  /// support, so the app refuses rather than fabricating (audit AI-07).
  static const minConceptsForViva = 5;

  bool get canExamine => conceptCount >= minConceptsForViva;

  int? get daysUntilExam {
    if (examDate == null) return null;
    final now = DateTime.now();
    return DateTime(examDate!.year, examDate!.month, examDate!.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }
}

/// An uploaded file and where it is in the pipeline.
@immutable
class Document {
  const Document({
    required this.id,
    required this.filename,
    required this.status,
    required this.byteSize,
    this.pageCount,
    this.errorMessage,
  });

  final String id;
  final String filename;

  /// pending · extracting · chunking · embedding · ready · failed
  final String status;
  final int byteSize;
  final int? pageCount;
  final String? errorMessage;

  bool get isReady => status == 'ready';
  bool get hasFailed => status == 'failed';
  bool get isProcessing => !isReady && !hasFailed;
}

/// Reads and writes through Supabase, under the signed-in user's RLS context.
///
/// Every method here is scoped by the database, not by a `where user_id = …`
/// the client could forget. That is the point of the RLS migration: a bug in
/// this file cannot leak another student's notes.
class Repository {
  const Repository();

  // -- Study library ------------------------------------------------------

  Future<Set<String>> starredConceptIds() async {
    final raw = Backend.user?.userMetadata?['starred_concept_ids'];
    if (raw is! List) return {};
    return {for (final id in raw) id.toString()};
  }

  Future<void> setConceptStarred(String conceptId, bool starred) async {
    final ids = await starredConceptIds();
    if (starred) {
      ids.add(conceptId);
    } else {
      ids.remove(conceptId);
    }
    await Backend.client.auth.updateUser(
      UserAttributes(data: {'starred_concept_ids': ids.toList()}),
    );
  }

  Future<StudyPreferences> studyPreferences() async {
    final metadata = Backend.user?.userMetadata;
    return StudyPreferences(
      dailyGoalMinutes:
          (metadata?['daily_goal_minutes'] as num?)?.toInt() ?? 20,
      desiredRetention:
          (metadata?['desired_retention'] as num?)?.toDouble() ?? 0.90,
    );
  }

  Future<void> updateStudyPreferences({
    required int dailyGoalMinutes,
    required double desiredRetention,
  }) async {
    await Backend.client.auth.updateUser(
      UserAttributes(data: {
        'daily_goal_minutes': dailyGoalMinutes,
        'desired_retention': desiredRetention,
      }),
    );
  }

  // -- Subjects -----------------------------------------------------------

  Future<List<Subject>> subjects() async {
    final subjectRowsFuture = Backend.client
        .from('subject')
        .select('id, name, exam_date, deleted_at')
        .isFilter('deleted_at', null)
        .order('created_at');
    final documentRowsFuture = Backend.client
        .from('document')
        .select('subject_id')
        .isFilter('deleted_at', null);
    final subjectData =
        await Future.wait([subjectRowsFuture, documentRowsFuture]);
    final rows = subjectData[0];
    final documentRows = subjectData[1];
    final documentCounts = <String, int>{};
    final conceptCounts = <String, int>{};
    for (final row in documentRows) {
      final id = row['subject_id'] as String;
      documentCounts[id] = (documentCounts[id] ?? 0) + 1;
    }
    final groundedBySubject = await Future.wait(rows.map((row) async {
      final id = row['id'] as String;
      final grounded = await Backend.client.rpc(
        'grounded_concepts',
        params: {'p_subject_id': id},
      );
      return MapEntry(id, [
        for (final concept in grounded as List) concept['id'] as String,
      ]);
    }));
    for (final entry in groundedBySubject) {
      conceptCounts[entry.key] = entry.value.length;
    }

    return [
      for (final row in rows)
        Subject(
          id: row['id'] as String,
          name: row['name'] as String,
          documentCount: documentCounts[row['id'] as String] ?? 0,
          conceptCount: conceptCounts[row['id'] as String] ?? 0,
          groundedConceptIds: groundedBySubject
              .firstWhere((entry) => entry.key == row['id'])
              .value,
          examDate: row['exam_date'] == null
              ? null
              : DateTime.parse(row['exam_date'] as String),
        ),
    ];
  }

  Future<Subject> createSubject(String name, {DateTime? examDate}) async {
    final row = await Backend.client
        .from('subject')
        .insert({
          'user_id': Backend.user!.id,
          'name': name,
          if (examDate != null)
            'exam_date': examDate.toIso8601String().split('T').first,
        })
        .select('id, name, exam_date')
        .single();

    return Subject(
      id: row['id'] as String,
      name: row['name'] as String,
      documentCount: 0,
      conceptCount: 0,
      examDate: row['exam_date'] == null
          ? null
          : DateTime.parse(row['exam_date'] as String),
    );
  }

  /// Sets or clears the exam date.
  ///
  /// This is not a cosmetic field: the scheduler refuses to place a review
  /// after it and pulls weak concepts well inside it, so setting one changes
  /// every interval the student is given from that point on.
  Future<void> setExamDate(String subjectId, DateTime? date) async {
    await Backend.client.from('subject').update({
      'exam_date': date?.toIso8601String().split('T').first,
    }).eq('id', subjectId);
  }

  /// Removes the subject and everything derived from it.
  ///
  /// Soft delete: `deleted_at` is set rather than rows destroyed, because the
  /// evaluation history is an append-only record and a student who deletes a
  /// subject by accident should not lose their transcript with it.
  Future<void> deleteSubject(String subjectId) async {
    await Backend.client
        .rpc('delete_subject', params: {'p_subject_id': subjectId});
  }

  /// Everything the account holds, for the export and deletion screens.
  Future<AccountSummary> accountSummary() async {
    final client = Backend.client;
    final documentsFuture = client.from('document').count();
    final chunksFuture = client.from('chunk').count();
    final answersFuture = client.from('answer').count();
    final subjectsFuture =
        client.from('subject').count().isFilter('deleted_at', null);
    return AccountSummary(
      subjects: await subjectsFuture,
      documents: await documentsFuture,
      passages: await chunksFuture,
      answers: await answersFuture,
      userId: Backend.user?.id ?? '',
      isAnonymous: Backend.user?.isAnonymous ?? true,
    );
  }

  // -- Documents ----------------------------------------------------------

  Future<List<Document>> documents(String subjectId) async {
    final rows = await Backend.client
        .from('document')
        .select('id, filename, status, byte_size, page_count, error_message')
        .eq('subject_id', subjectId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return [
      for (final r in rows)
        Document(
          id: r['id'] as String,
          filename: r['filename'] as String,
          status: r['status'] as String? ?? 'pending',
          byteSize: r['byte_size'] as int,
          pageCount: r['page_count'] as int?,
          errorMessage: r['error_message'] as String?,
        ),
    ];
  }

  /// Uploads a file and registers it for ingestion.
  ///
  /// Storage first, row second. If the row insert fails the object is removed
  /// again — an orphaned blob costs money forever and belongs to nobody, and
  /// a document row pointing at a missing object is worse still.
  Future<Document> upload({
    required String subjectId,
    required String filename,
    required Uint8List bytes,
    required String contentHash,
    String mimeType = 'application/pdf',
  }) async {
    final userId = Backend.user!.id;
    // The storage RLS policy requires the first path segment to be the
    // owner's uid, so this layout is load-bearing, not cosmetic.
    final path = '$userId/$subjectId/$contentHash-$filename';

    await Backend.client.storage.from('documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    try {
      final row = await Backend.client
          .from('document')
          .insert({
            'subject_id': subjectId,
            'user_id': userId,
            'filename': filename,
            'storage_path': path,
            'mime_type': mimeType,
            'byte_size': bytes.length,
            'content_hash': contentHash,
            'status': 'pending',
          })
          .select('id, filename, status, byte_size, page_count')
          .single();

      return Document(
        id: row['id'] as String,
        filename: row['filename'] as String,
        status: row['status'] as String? ?? 'pending',
        byteSize: row['byte_size'] as int,
        pageCount: row['page_count'] as int?,
      );
    } catch (_) {
      await Backend.client.storage.from('documents').remove([path]);
      rethrow;
    }
  }

  /// Runs ingestion for an uploaded document.
  ///
  /// The Edge Function holds the model key, so this call carries only the
  /// document id and the caller's session. It is deliberately awaited rather
  /// than fired and forgotten: a student who uploads notes and is told
  /// nothing assumes the app is broken.
  Future<IngestResult> ingest(String documentId) async {
    final res = await Backend.client.functions.invoke(
      'ingest',
      body: {'document_id': documentId},
    );
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return IngestResult(
        pages: (data['pages'] as num?)?.toInt() ?? 0,
        chunks: (data['chunks'] as num?)?.toInt() ?? 0,
        concepts: (data['concepts'] as num?)?.toInt() ?? 0,
        edges: (data['edges'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(
      data is Map && data['error'] != null ? data['error'] : 'Ingestion failed',
    );
  }

  /// Supabase throws on non-2xx responses. Preserve structured refusals so
  /// the UI can show upload guidance instead of a raw transport exception.
  Future<dynamic> _examine(Map<String, dynamic> body) async {
    try {
      return (await Backend.client.functions.invoke('examine', body: body))
          .data;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] == 'insufficient_material') {
        throw InsufficientMaterial(
          found: (details['concepts'] as num?)?.toInt() ?? 0,
          needed: (details['needed'] as num?)?.toInt() ?? 5,
          message:
              details['message'] as String? ?? 'Upload more notes to begin.',
        );
      }
      if (details is Map && details['message'] is String) {
        throw ExaminerFailure(details['message'] as String);
      }
      throw ExaminerFailure(switch (error.status) {
        401 => 'Your session expired. Sign in again to continue.',
        429 => 'The examiner has reached its current limit. Try again later.',
        _ =>
          'The examiner could not complete this request. Your answer is still here; try again.',
      });
    }
  }

  // -- Examination --------------------------------------------------------

  /// Asks the examiner for a question grounded in this subject's notes.
  ///
  /// Throws [InsufficientMaterial] when the notes cannot support a viva —
  /// the refusal is a feature, so it gets its own type rather than a generic
  /// error the UI would have to string-match.
  Future<VivaQuestion> nextQuestion({
    required String subjectId,
    String? sessionId,
    String? conceptId,
    String? mode,
  }) async {
    final data = await _examine({
      'action': 'question',
      'subject_id': subjectId,
      if (sessionId != null) 'session_id': sessionId,
      if (conceptId != null) 'concept_id': conceptId,
      if (mode != null) 'mode': mode,
    });
    if (data is Map && data['ok'] == true) {
      final q = data['question'] as Map;
      return VivaQuestion(
        id: q['id'] as String,
        sessionId: data['session_id'] as String,
        text: q['text'] as String,
        concept: data['concept'] as String? ?? '',
        conceptId: data['concept_id'] as String? ?? '',
        ordinal: (q['ordinal'] as num?)?.toInt() ?? 1,
        difficulty: (q['difficulty_level'] as num?)?.toInt() ?? 2,
        sourceChunkIds: [
          for (final source in (data['sources'] as List? ?? const []))
            if (source is Map && source['chunk_id'] != null)
              source['chunk_id'].toString(),
        ],
      );
    }
    if (data is Map && data['error'] == 'insufficient_material') {
      throw InsufficientMaterial(
        found: (data['concepts'] as num?)?.toInt() ?? 0,
        needed: (data['needed'] as num?)?.toInt() ?? 5,
        message: data['message'] as String? ?? 'Not enough material.',
      );
    }
    throw Exception(data is Map
        ? data['message'] ?? data['error']
        : 'Could not ask a question');
  }

  /// Asks the examiner to press on the previous answer.
  ///
  /// Returns null when the examiner judged there was nothing worth pressing —
  /// that decision lives server-side, so a client cannot talk it into
  /// interrogating a student who simply got the question wrong.
  Future<VivaQuestion?> followUp({required String questionId}) async {
    final data = await _examine({
      'action': 'followup',
      'question_id': questionId,
    });
    if (data is Map && data['ok'] == true) {
      if (data['follow_up'] != true) return null;
      final q = data['question'] as Map;
      return VivaQuestion(
        id: q['id'] as String,
        sessionId: data['session_id'] as String,
        text: q['text'] as String,
        concept: data['concept'] as String? ?? '',
        conceptId: data['concept_id'] as String? ?? '',
        ordinal: (q['ordinal'] as num?)?.toInt() ?? 1,
        difficulty: (q['difficulty_level'] as num?)?.toInt() ?? 2,
        isFollowUp: true,
        depth: (data['depth'] as num?)?.toInt() ?? 1,
        sourceChunkIds: [
          for (final source in (data['sources'] as List? ?? const []))
            if (source is Map && source['chunk_id'] != null)
              source['chunk_id'].toString(),
        ],
      );
    }
    throw Exception(
        data is Map ? data['message'] ?? data['error'] : 'Could not follow up');
  }

  Future<VivaResult> evaluate({
    required String questionId,
    required String answer,
  }) async {
    final data = await _examine({
      'action': 'evaluate',
      'question_id': questionId,
      'answer': answer,
    });
    if (data is Map && data['ok'] == true) {
      final rubric = (data['rubric'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      );
      return VivaResult(
        followUpAvailable: data['follow_up_available'] == true,
        evaluationId: data['evaluation_id'] as String? ?? '',
        composite: (data['composite'] as num).toDouble(),
        verdict: data['verdict'] as String? ?? '',
        feedback: data['feedback'] as String? ?? '',
        expected: [
          for (final e in (data['expected'] as List? ?? [])) e.toString(),
        ],
        rubric: rubric,
        gaps: [
          for (final g in (data['gaps'] as List? ?? []))
            Gap(
              label: g['label'] as String? ?? '',
              detail: g['detail'] as String? ?? '',
              page: (g['page'] as num?)?.toInt(),
              chunkId: g['chunk_id'] as String?,
            ),
        ],
      );
    }
    throw Exception(data is Map
        ? data['message'] ?? data['error']
        : 'Could not mark the answer');
  }

  // -- Home / cross-subject -----------------------------------------------

  /// Everything the Home screen shows, in one round trip per table.
  ///
  /// Readiness across subjects is weighted by concept count rather than
  /// averaged flat: a subject with forty concepts and one with three should
  /// not count equally toward "am I ready".
  Future<HomeSummary> homeSummary() async {
    final subjectsFuture = this.subjects();
    final standingFuture = Backend.client
        .from('concept_standing')
        .select('concept_id, subject_id, effective_mastery');
    final dueRowsFuture = Backend.client
        .from('revision_queue')
        .select(
            'concept_id, concept_name, mastery_pct, due_at, estimated_minutes, bucket, subject_id')
        .inFilter('bucket', ['today', 'unscheduled'])
        .order('mastery_pct')
        .limit(12);

    // Streak from the answer log: consecutive days ending today or yesterday.
    // Yesterday still counts, so a student who has not studied *yet today*
    // is not told their streak is already broken.
    final answeredFuture = Backend.client
        .from('answer')
        .select('created_at')
        .order('created_at', ascending: false)
        .limit(400);
    final answeredTotalFuture = Backend.client.from('answer').count();

    // PostgREST builders execute only when awaited. Collect them together so
    // independent reads do not accumulate six network round trips in series.
    final results = await Future.wait<dynamic>([
      subjectsFuture,
      standingFuture,
      dueRowsFuture,
      answeredFuture,
      answeredTotalFuture,
    ]);
    final subjects = results[0] as List<Subject>;
    final usableIds = subjects.expand((s) => s.groundedConceptIds).toSet();
    final standing = (results[1] as List<Map<String, dynamic>>)
        .where((row) => usableIds.contains(row['concept_id']))
        .toList();
    final dueRows = (results[2] as List<Map<String, dynamic>>)
        .where((row) => usableIds.contains(row['concept_id']))
        .toList();
    final answered = results[3] as List<Map<String, dynamic>>;
    final answeredTotal = results[4] as int;

    // Readiness is the mean effective mastery across the complete syllabus;
    // unexamined concepts contribute zero. This is equivalent to the old
    // per-subject RPC loop, but it needs one request regardless of how many
    // subjects the student has.
    final readiness = standing.isEmpty
        ? 0.0
        : standing.fold<double>(
              0,
              (sum, row) =>
                  sum + ((row['effective_mastery'] as num?)?.toDouble() ?? 0),
            ) /
            standing.length;

    final days = <DateTime>{};
    for (final a in answered) {
      final t = DateTime.parse(a['created_at'] as String).toLocal();
      days.add(DateTime(t.year, t.month, t.day));
    }
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return HomeSummary(
      subjects: subjects,
      readiness: readiness,
      streakDays: streak,
      answeredTotal: answeredTotal,
      due: [
        for (final r in dueRows)
          RevisionItem(
            conceptId: r['concept_id'] as String,
            name: r['concept_name'] as String? ?? '',
            mastery: (r['mastery_pct'] as num?)?.toDouble() ?? 0,
            minutes: (r['estimated_minutes'] as num?)?.toInt() ?? 10,
            bucket: r['bucket'] as String? ?? 'unscheduled',
            subjectId: r['subject_id'] as String?,
            dueAt: r['due_at'] == null
                ? null
                : DateTime.parse(r['due_at'] as String),
          ),
      ],
    );
  }

  /// Returns all concepts that are scheduled for revision.
  Future<List<RevisionItem>> dueConcepts() async {
    final dueRows = await Backend.client
        .from('revision_queue')
        .select(
            'concept_id, concept_name, mastery_pct, due_at, estimated_minutes, bucket, subject_id')
        .not('due_at', 'is', null)
        .order('due_at', ascending: true);

    return [
      for (final r in dueRows)
        if (r['due_at'] != null)
          RevisionItem(
            conceptId: r['concept_id'] as String,
            name: r['concept_name'] as String? ?? '',
            mastery: (r['mastery_pct'] as num?)?.toDouble() ?? 0,
            minutes: (r['estimated_minutes'] as num?)?.toInt() ?? 10,
            bucket: r['bucket'] as String? ?? 'unscheduled',
            subjectId: r['subject_id'] as String?,
            dueAt: DateTime.parse(r['due_at'] as String),
          ),
    ];
  }

  /// The improvement curve and activity stats behind the Progress tab.
  Future<Analytics> analytics() async {
    final events = await Backend.client
        .from('concept_mastery_event')
        .select('new_mastery, prior_mastery, rating, occurred_at')
        .order('occurred_at')
        .limit(500);

    final answers = await Backend.client
        .from('answer')
        .select('created_at, duration_ms')
        .limit(500);

    final evaluations = await Backend.client
        .from('evaluation')
        .select('composite_score, created_at')
        .order('created_at')
        .limit(500);

    final scores = [
      for (final e in evaluations) (e['composite_score'] as num).toDouble(),
    ];

    // Improvement is measured against the student's own start, not a cohort:
    // there is no cohort, and inventing one would be dishonest.
    final firstFive = scores.take(5).toList();
    final lastFive = scores.reversed.take(5).toList();
    final improvement = (firstFive.isEmpty || lastFive.isEmpty)
        ? 0.0
        : (lastFive.reduce((a, b) => a + b) / lastFive.length) -
            (firstFive.reduce((a, b) => a + b) / firstFive.length);

    final minutes = answers.fold<int>(
      0,
      (sum, a) => sum + (((a['duration_ms'] as num?)?.toInt() ?? 0) ~/ 60000),
    );

    final dates = <DateTime>[];
    for (final e in events) {
      final dt = DateTime.tryParse(e['occurred_at']?.toString() ?? '');
      if (dt != null) dates.add(dt);
    }
    for (final a in answers) {
      final dt = DateTime.tryParse(a['created_at']?.toString() ?? '');
      if (dt != null) dates.add(dt);
    }

    return Analytics(
      scores: scores,
      questionsAnswered: answers.length,
      reviewsLogged: events.length,
      lapses: events.where((e) => (e['rating'] as num?)?.toInt() == 1).length,
      improvement: improvement,
      minutesPractised: minutes,
      reviewDates: dates,
    );
  }

  /// The passage behind a citation.
  ///
  /// Read back from the chunk table rather than trusted from the model: this
  /// is the text the question was actually built on, so a student who opens
  /// it is seeing the evidence, not a paraphrase of it.
  Future<Passage> passage(String chunkId) async {
    final row = await Backend.client
        .from('chunk')
        .select('id, content, page_number, document:document_id (filename)')
        .eq('id', chunkId)
        .single();
    return Passage(
      chunkId: row['id'] as String,
      content: row['content'] as String,
      page: (row['page_number'] as num?)?.toInt(),
      filename:
          (row['document'] as Map?)?['filename'] as String? ?? 'your notes',
    );
  }

  /// Soft-deletes a document. The rows stay for the audit trail; the student
  /// stops seeing it and it stops counting toward coverage.
  Future<void> removeDocument(String documentId) async {
    await Backend.client
        .rpc('delete_document', params: {'p_document_id': documentId});
  }

  /// Records a challenge to a mark.
  ///
  /// The score is stored on the dispute rather than read back later, because
  /// the mark is append-only but the rubric weights behind it are not — a
  /// disagreement is only interpretable against the version that produced it.
  Future<void> disputeEvaluation({
    required String evaluationId,
    required String reason,
    required String detail,
  }) async {
    final evaluation = await Backend.client
        .from('evaluation')
        .select('composite_score, rubric_version')
        .eq('id', evaluationId)
        .single();

    await Backend.client.from('evaluation_dispute').insert({
      'evaluation_id': evaluationId,
      'user_id': Backend.user!.id,
      'reason': reason,
      if (detail.isNotEmpty) 'detail': detail,
      'scored': evaluation['composite_score'],
      'rubric_version': evaluation['rubric_version'] ?? 'v1',
    });
  }

  /// Past sittings, newest first.
  ///
  /// Every viva is already stored; nothing showed it back. A transcript is
  /// what turns a score into something a student can revise from — and it is
  /// the only place they can see whether a concept improved *between*
  /// sittings rather than within one.
  Future<List<PastSession>> sessions({int limit = 25}) async {
    final rows = await Backend.client
        .from('viva_session')
        .select('id, mode, started_at, subject:subject_id (name)')
        .order('started_at', ascending: false)
        .limit(limit);

    final sessions = <PastSession>[];
    for (final row in rows) {
      final id = row['id'] as String;
      // Answers and marks hang off questions, so one join per session gives
      // the whole sitting without a second round trip per question.
      final questions = await Backend.client
          .from('question')
          .select('id, text, ordinal, concept:concept_id (canonical_name), '
              'answer (id, text, evaluation (composite_score))')
          .eq('session_id', id)
          .order('ordinal');

      final marks = <double>[];
      final items = <PastAnswer>[];
      for (final q in questions) {
        final answers = (q['answer'] as List?) ?? const [];
        if (answers.isEmpty) continue;
        final answer = answers.first as Map;
        final evaluations = (answer['evaluation'] as List?) ?? const [];
        final score = evaluations.isEmpty
            ? null
            : (evaluations.first as Map)['composite_score'] as num?;
        if (score != null) marks.add(score.toDouble());
        items.add(PastAnswer(
          question: q['text'] as String? ?? '',
          concept: (q['concept'] as Map?)?['canonical_name'] as String? ?? '',
          answer: answer['text'] as String? ?? '',
          score: score?.toDouble(),
        ));
      }
      // A session with no answered question is an abandoned one; showing it
      // would pad the history with nothing to read.
      if (items.isEmpty) continue;

      sessions.add(PastSession(
        id: id,
        subject: (row['subject'] as Map?)?['name'] as String? ?? '',
        mode: row['mode'] as String? ?? 'practice',
        startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
        answers: items,
        mean: marks.isEmpty ? 0 : marks.reduce((a, b) => a + b) / marks.length,
      ));
    }
    return sessions;
  }

  /// Everything about one concept: its standing, its history, and where it
  /// sits in the graph.
  ///
  /// Both directions of the edge matter and they answer different questions.
  /// Prerequisites tell a student *why* this is hard; dependents tell them
  /// what fixing it unlocks — which is the argument for spending the next
  /// twenty minutes here rather than somewhere else.
  Future<ConceptDetail> conceptDetail(String conceptId) async {
    final concept = await Backend.client
        .from('concept')
        .select('id, canonical_name, description, importance, subject_id')
        .eq('id', conceptId)
        .single();
    final subjectId = concept['subject_id'] as String;

    final mastery = await Backend.client
        .from('concept_mastery')
        .select(
            'mastery_pct, stability, difficulty, due_at, review_count, lapses')
        .eq('concept_id', conceptId)
        .maybeSingle();

    final history = await Backend.client
        .from('concept_mastery_event')
        .select('prior_mastery, new_mastery, rating, occurred_at')
        .eq('concept_id', conceptId)
        .order('occurred_at')
        .limit(60);

    final edges = await Backend.client
        .from('concept_edge')
        .select('prerequisite_concept_id, dependent_concept_id')
        .eq('subject_id', subjectId);

    final names = await Backend.client
        .from('concept')
        .select('id, canonical_name')
        .eq('subject_id', subjectId);
    final byId = {
      for (final n in names) n['id'] as String: n['canonical_name'] as String,
    };

    final masteryById = <String, double>{};
    final allMastery = await Backend.client
        .from('concept_mastery')
        .select('concept_id, mastery_pct')
        .eq('subject_id', subjectId);
    for (final m in allMastery) {
      masteryById[m['concept_id'] as String] =
          (m['mastery_pct'] as num).toDouble();
    }

    List<ConceptLink> links(String matchOn, String takeFrom) => [
          for (final e in edges)
            if (e[matchOn] == conceptId && byId.containsKey(e[takeFrom]))
              ConceptLink(
                id: e[takeFrom] as String,
                name: byId[e[takeFrom]]!,
                mastery: masteryById[e[takeFrom]],
              ),
        ];

    return ConceptDetail(
      id: conceptId,
      subjectId: subjectId,
      name: concept['canonical_name'] as String,
      description: concept['description'] as String?,
      importance: (concept['importance'] as num?)?.toInt() ?? 2,
      mastery: (mastery?['mastery_pct'] as num?)?.toDouble(),
      stability: (mastery?['stability'] as num?)?.toDouble(),
      difficulty: (mastery?['difficulty'] as num?)?.toDouble(),
      reviews: (mastery?['review_count'] as num?)?.toInt() ?? 0,
      lapses: (mastery?['lapses'] as num?)?.toInt() ?? 0,
      dueAt: mastery?['due_at'] == null
          ? null
          : DateTime.parse(mastery!['due_at'] as String).toLocal(),
      history: [
        for (final h in history)
          MasteryPoint(
            value: (h['new_mastery'] as num).toDouble(),
            rating: (h['rating'] as num?)?.toInt() ?? 3,
            at: DateTime.parse(h['occurred_at'] as String).toLocal(),
          ),
      ],
      prerequisites: links('dependent_concept_id', 'prerequisite_concept_id'),
      unlocks: links('prerequisite_concept_id', 'dependent_concept_id'),
    );
  }

  // -- Concepts and progress ----------------------------------------------

  /// Concepts with their mastery, weakest first.
  ///
  /// Untested concepts sort last, not first: an absence of evidence is not
  /// evidence of weakness, and putting them at the top would send a student
  /// to revise something they may already know.
  Future<List<ConceptRow>> concepts(String subjectId) async {
    final rows = await Backend.client.rpc(
      'grounded_concepts',
      params: {'p_subject_id': subjectId},
    );
    if (rows.isEmpty) return const [];

    final mastery = await Backend.client
        .from('concept_mastery')
        .select('concept_id, mastery_pct, review_count, due_at, gap_severity')
        .eq('subject_id', subjectId);
    final byConcept = {for (final m in mastery) m['concept_id'] as String: m};

    // Prerequisite edges, so a weak concept can name what is holding it back.
    final edges = await Backend.client
        .from('concept_edge')
        .select('prerequisite_concept_id, dependent_concept_id')
        .eq('subject_id', subjectId);

    final names = {
      for (final r in rows) r['id'] as String: r['canonical_name'] as String,
    };

    String? blockedBy(String conceptId) {
      String? worstName;
      double worstMastery = 100;
      for (final e in edges) {
        if (e['dependent_concept_id'] != conceptId) continue;
        final prereqId = e['prerequisite_concept_id'] as String;
        final pct = (byConcept[prereqId]?['mastery_pct'] as num?)?.toDouble();
        // Only a prerequisite that is itself weak is worth naming; a strong
        // one is not what is holding anything back.
        if (pct != null && pct < 50 && pct < worstMastery) {
          worstMastery = pct;
          worstName = names[prereqId];
        }
      }
      return worstName;
    }

    final list = [
      for (final r in rows)
        ConceptRow(
          id: r['id'] as String,
          name: r['canonical_name'] as String,
          description: (r['description'] as String?) ??
              (r['source_evidence'] as String?),
          importance: (r['importance'] as num?)?.toInt() ?? 2,
          mastery: (byConcept[r['id']]?['mastery_pct'] as num?)?.toDouble(),
          reviews: (byConcept[r['id']]?['review_count'] as num?)?.toInt() ?? 0,
          blockedBy: blockedBy(r['id'] as String),
        ),
    ];

    list.sort((a, b) {
      if ((a.mastery == null) != (b.mastery == null)) {
        return a.mastery == null ? 1 : -1;
      }
      if (a.mastery == null) return b.importance.compareTo(a.importance);
      return a.mastery!.compareTo(b.mastery!);
    });
    return list;
  }

  /// Readiness, straight from the database function so the number the student
  /// sees is the number the server computed.
  Future<Readiness> readiness(String subjectId) async {
    final row = await Backend.client
        .rpc('subject_readiness', params: {'p_subject_id': subjectId}).single();
    return Readiness(
      totalConcepts: (row['total_concepts'] as num?)?.toInt() ?? 0,
      examinedConcepts: (row['examined_concepts'] as num?)?.toInt() ?? 0,
      coverage: (row['coverage_pct'] as num?)?.toDouble() ?? 0,
      meanMastery: (row['mean_mastery'] as num?)?.toDouble() ?? 0,
    );
  }

  /// What is due, from the FSRS schedule. The buckets are computed from
  /// `due_at` in the student's timezone, not stored — so "today" is still
  /// correct tomorrow.
  Future<List<RevisionItem>> revision(String subjectId) async {
    final grounded = await Backend.client.rpc(
      'grounded_concepts',
      params: {'p_subject_id': subjectId},
    );
    final ids = [
      for (final concept in grounded as List) concept['id'] as String
    ];
    if (ids.isEmpty) return const [];
    final rows = await Backend.client
        .from('revision_queue')
        .select(
            'concept_id, concept_name, mastery_pct, due_at, estimated_minutes, bucket')
        .eq('subject_id', subjectId)
        .inFilter('concept_id', ids)
        .order('due_at', nullsFirst: false)
        .limit(30);
    return [
      for (final r in rows)
        RevisionItem(
          conceptId: r['concept_id'] as String,
          name: r['concept_name'] as String? ?? '',
          mastery: (r['mastery_pct'] as num?)?.toDouble() ?? 0,
          minutes: (r['estimated_minutes'] as num?)?.toInt() ?? 10,
          bucket: r['bucket'] as String? ?? 'unscheduled',
          dueAt: r['due_at'] == null
              ? null
              : DateTime.parse(r['due_at'] as String),
        ),
    ];
  }

  /// Submit manual study results (Flashcards, Match, Test modes).
  /// [conceptScores] is a map of Concept ID to a score from 0-100.
  Future<void> submitStudyResults(
      String subjectId, Map<String, int> conceptScores) async {
    if (conceptScores.isEmpty) return;

    final resultsList = conceptScores.entries
        .map((e) => {
              'concept_id': e.key,
              'score': e.value,
            })
        .toList();

    await Backend.client.rpc(
      'submit_study_results',
      params: {
        'p_subject_id': subjectId,
        'p_results': resultsList,
      },
    );
  }
}

@immutable
class ConceptRow {
  const ConceptRow({
    required this.id,
    required this.name,
    required this.importance,
    this.description,
    this.mastery,
    this.reviews = 0,
    this.blockedBy,
  });

  final String id;
  final String name;
  final String? description;
  final int importance;

  /// Null means never examined — not the same as zero, and not drawn the same.
  final double? mastery;
  final int reviews;

  /// The weakest prerequisite standing in this concept's way. The line no
  /// competing study app can draw, because it needs the edge graph.
  final String? blockedBy;
}

@immutable
class StudyPreferences {
  const StudyPreferences({
    required this.dailyGoalMinutes,
    required this.desiredRetention,
  });

  final int dailyGoalMinutes;
  final double desiredRetention;
}

@immutable
class Readiness {
  const Readiness({
    required this.totalConcepts,
    required this.examinedConcepts,
    required this.coverage,
    required this.meanMastery,
  });

  final int totalConcepts;
  final int examinedConcepts;

  /// How much of the syllabus has been examined at all.
  final double coverage;
  final double meanMastery;

  /// Coverage and mastery combined, with untested concepts counting against
  /// the score rather than being quietly excluded from the average.
  double get score {
    if (totalConcepts == 0) return 0;
    return (meanMastery * examinedConcepts / totalConcepts).clamp(0, 100);
  }
}

@immutable
class RevisionItem {
  const RevisionItem({
    required this.conceptId,
    required this.name,
    required this.mastery,
    required this.minutes,
    required this.bucket,
    this.dueAt,
    this.subjectId,
  });

  final String? subjectId;

  final String conceptId;
  final String name;
  final double mastery;
  final int minutes;

  /// today · tomorrow · this_week · before_exam · unscheduled
  final String bucket;
  final DateTime? dueAt;
}

/// What ingestion produced. Shown to the student so the wait has a payoff.
@immutable
class IngestResult {
  const IngestResult({
    required this.pages,
    required this.chunks,
    required this.concepts,
    required this.edges,
  });

  final int pages;
  final int chunks;
  final int concepts;

  /// Prerequisite links found between concepts — the graph that lets the app
  /// say *why* a concept is failing, not just that it is.
  final int edges;
}

/// The notes cannot support a viva yet. Refusing is the product working, not
/// failing, so the UI shows the numbers rather than an error.
class InsufficientMaterial implements Exception {
  const InsufficientMaterial({
    required this.found,
    required this.needed,
    required this.message,
  });

  final int found;
  final int needed;
  final String message;

  @override
  String toString() => message;
}

@immutable
class VivaQuestion {
  const VivaQuestion({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.concept,
    required this.ordinal,
    required this.difficulty,
    this.conceptId = '',
    this.isFollowUp = false,
    this.depth = 0,
    this.sourceChunkIds = const [],
  });

  final String id;
  final String conceptId;
  final String sessionId;
  final String text;
  final String concept;
  final int ordinal;
  final int difficulty;

  /// This question presses on the previous answer rather than opening a new
  /// line. The screen says so, because being probed should feel different
  /// from being asked something new.
  final bool isFollowUp;
  final int depth;

  /// Exact note passages that passed server-side question-grounding checks.
  final List<String> sourceChunkIds;
}

@immutable
class Gap {
  const Gap({
    required this.label,
    required this.detail,
    this.page,
    this.chunkId,
  });

  final String label;
  final String detail;

  /// The page in the student's own notes. Present because the citation was
  /// verified server-side, not because the model claimed it.
  final int? page;

  /// The passage itself, so the citation opens rather than just naming a page
  /// the student has to go and find.
  final String? chunkId;
}

@immutable
class VivaResult {
  const VivaResult({
    this.followUpAvailable = false,
    required this.evaluationId,
    required this.composite,
    required this.verdict,
    required this.feedback,
    required this.rubric,
    required this.gaps,
    this.expected = const [],
  });

  /// What a complete answer needed to contain, decided when the question was
  /// generated — not reverse-engineered from the mark afterwards.
  final List<String> expected;

  /// Identifies the mark, so a student can challenge this specific one.
  final String evaluationId;

  /// The examiner has something to press on. Only true for a near-miss with
  /// an identified gap — a wrong answer gets moved on from, not interrogated.
  final bool followUpAvailable;

  final double composite;
  final String verdict;
  final String feedback;

  /// Six dimensions. Confidence is deliberately absent — it is prosodic and
  /// cannot be read from typed text.
  final Map<String, double> rubric;
  final List<Gap> gaps;
}

@immutable
class AccountSummary {
  const AccountSummary({
    required this.subjects,
    required this.documents,
    required this.passages,
    required this.answers,
    required this.userId,
    required this.isAnonymous,
  });

  final int subjects;
  final int documents;
  final int passages;
  final int answers;
  final String userId;

  /// An anonymous account has no email and cannot be recovered on another
  /// device — worth saying plainly before someone relies on it.
  final bool isAnonymous;
}

@immutable
class HomeSummary {
  const HomeSummary({
    required this.subjects,
    required this.readiness,
    required this.streakDays,
    required this.answeredTotal,
    required this.due,
  });

  final List<Subject> subjects;

  /// Weighted by concept count across subjects, so a large syllabus counts
  /// for more than a three-concept one.
  final double readiness;
  final int streakDays;
  final int answeredTotal;
  final List<RevisionItem> due;

  bool get isEmpty => subjects.isEmpty;
  int get dueMinutes => due.fold(0, (sum, r) => sum + r.minutes);
}

@immutable
class Analytics {
  const Analytics({
    required this.scores,
    required this.questionsAnswered,
    required this.reviewsLogged,
    required this.lapses,
    required this.improvement,
    required this.minutesPractised,
    this.reviewDates = const [],
  });

  /// Every composite score, oldest first — the improvement curve.
  final List<double> scores;
  final int questionsAnswered;
  final int reviewsLogged;

  /// Reviews rated "again". Tracked separately because a lapse is a different
  /// event from a slow success and the scheduler treats it differently.
  final int lapses;
  final double improvement;
  final int minutesPractised;
  final List<DateTime> reviewDates;

  double get meanScore =>
      scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;
}

@immutable
class Passage {
  const Passage({
    required this.chunkId,
    required this.content,
    required this.page,
    required this.filename,
  });

  final String chunkId;
  final String content;
  final int? page;
  final String filename;
}

@immutable
class PastSession {
  const PastSession({
    required this.id,
    required this.subject,
    required this.mode,
    required this.startedAt,
    required this.answers,
    required this.mean,
  });

  final String id;
  final String subject;
  final String mode;
  final DateTime startedAt;
  final List<PastAnswer> answers;
  final double mean;
}

@immutable
class PastAnswer {
  const PastAnswer({
    required this.question,
    required this.concept,
    required this.answer,
    required this.score,
  });

  final String question;
  final String concept;
  final String answer;

  /// Null when the answer was given but never marked — a session interrupted
  /// mid-evaluation, which is different from a zero.
  final double? score;
}

@immutable
class ConceptDetail {
  const ConceptDetail({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.description,
    required this.importance,
    required this.mastery,
    required this.stability,
    required this.difficulty,
    required this.reviews,
    required this.lapses,
    required this.dueAt,
    required this.history,
    required this.prerequisites,
    required this.unlocks,
  });

  final String id;
  final String subjectId;
  final String name;
  final String? description;
  final int importance;

  /// Null when never examined, which is not the same as zero.
  final double? mastery;

  /// Days the scheduler expects this to survive in memory.
  final double? stability;
  final double? difficulty;
  final int reviews;
  final int lapses;
  final DateTime? dueAt;
  final List<MasteryPoint> history;

  /// What must be understood first. The weakest of these is what is actually
  /// holding this concept back.
  final List<ConceptLink> prerequisites;

  /// What improving this concept releases.
  final List<ConceptLink> unlocks;

  ConceptLink? get weakestPrerequisite {
    final weak = prerequisites
        .where((p) => p.mastery != null && p.mastery! < 50)
        .toList()
      ..sort((a, b) => a.mastery!.compareTo(b.mastery!));
    return weak.isEmpty ? null : weak.first;
  }
}

@immutable
class ConceptLink {
  const ConceptLink({required this.id, required this.name, this.mastery});

  final String id;
  final String name;
  final double? mastery;
}

@immutable
class MasteryPoint {
  const MasteryPoint({
    required this.value,
    required this.rating,
    required this.at,
  });

  final double value;

  /// 1 again · 2 hard · 3 good · 4 easy. A lapse is drawn differently from a
  /// slow success because the scheduler treats them differently.
  final int rating;
  final DateTime at;
}

/// A recovery message intended for the student, without exception prefixes.
class ExaminerFailure implements Exception {
  const ExaminerFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
