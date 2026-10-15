import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_client.dart';
import '../../design/bold.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _spaces = [], _subjects = [], _turns = [];
  Map<String, dynamic>? _space;
  String? _subjectId, _error, _pendingId;
  String _pendingText = '';
  bool _loading = true, _sending = false;
  int _loadVersion = 0;
  SupabaseClient get _db => Backend.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        _db
            .from('chat_space')
            .select()
            .order('created_at', ascending: false)
            .limit(100),
        _db
            .from('subject')
            .select('id,name')
            .isFilter('deleted_at', null)
            .order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _spaces = data[0];
        _subjects = data[1];
      });
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not load your conversations. Please retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> space) async {
    if (_sending) return;
    final version = ++_loadVersion;
    setState(() {
      _space = space;
      _subjectId = space['subject_id'];
      _turns = [];
      _loading = true;
      _error = null;
      _input.clear();
      _pendingId = null;
    });
    try {
      final turns = await _db
          .from('chat_turn')
          .select()
          .eq('space_id', space['id'])
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted && version == _loadVersion)
        setState(() => _turns = turns.reversed.toList());
      _toBottom();
    } catch (_) {
      if (mounted && version == _loadVersion)
        setState(() => _error =
            'Could not open this conversation. Choose it again to retry.');
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  void _new() {
    if (_sending) return;
    _loadVersion++;
    setState(() {
      _space = null;
      _subjectId = null;
      _turns = [];
      _error = null;
      _loading = false;
      _pendingId = null;
      _input.clear();
    });
  }

  String _id() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients)
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _send() async {
    final message = _input.text.trim();
    if (_sending || _loading || message.isEmpty) return;
    if (_pendingText != message) _pendingId = null;
    _pendingId ??= _id();
    _pendingText = message;
    setState(() {
      _sending = true;
      _error = null;
    });
    _toBottom();
    try {
      if (_space == null) {
        final space = await _db
            .from('chat_space')
            .insert({
              'title': message.length > 70
                  ? '${message.substring(0, 67)}…'
                  : message,
              'subject_id': _subjectId
            })
            .select()
            .single();
        if (!mounted) return;
        setState(() {
          _space = space;
          _spaces.insert(0, space);
        });
      }
      final response = await _db.functions.invoke('chat', body: {
        'id': _pendingId,
        'space_id': _space!['id'],
        'message': message
      });
      if (!mounted) return;
      final turn = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        if (!_turns.any((t) => t['id'] == turn['id'])) _turns.add(turn);
        _input.clear();
        _pendingId = null;
      });
      _toBottom();
    } on FunctionException catch (e) {
      if (mounted)
        setState(() => _error = e.details is Map
            ? (e.details['message']?.toString() ??
                'Could not send. Please retry.')
            : 'Could not send. Please retry.');
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Connection interrupted. Your message is kept below. Retry when you are ready.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _history() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .65,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Your conversations', style: T.title)),
                  Expanded(
                      child: _spaces.isEmpty
                          ? const Center(
                              child: Text(
                                  'Your first conversation will appear here.'))
                          : ListView.builder(
                              itemCount: _spaces.length,
                              itemBuilder: (context, i) => ListTile(
                                  title: Text(_spaces[i]['title']),
                                  subtitle: Text(
                                      _spaces[i]['subject_id'] == null
                                          ? 'General knowledge'
                                          : 'Study notes'),
                                  leading:
                                      const Icon(Icons.chat_bubble_outline),
                                  onTap: () =>
                                      Navigator.pop(context, _spaces[i])))),
                ]))));
    if (selected != null && mounted) await _open(selected);
  }

  Widget _message(String text, {required bool user}) => Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            constraints: const BoxConstraints(maxWidth: 720),
            decoration: BoxDecoration(
                color: user ? Bold.brand : Bold.cardOf(context),
                borderRadius: BorderRadius.circular(18)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user ? 'You' : 'ViaX',
                  style: T.small.copyWith(
                      color: user ? Colors.white70 : Bold.slateOf(context))),
              const SizedBox(height: 8),
              if (user)
                SelectableText(text,
                    style: T.body.copyWith(color: Colors.white, height: 1.55)),
              if (!user)
                MarkdownBody(
                  data: text,
                  selectable: true,
                  sizedImageBuilder: (_) => const Text('Image omitted'),
                  onTapLink: (_, href, __) async {
                    final uri = Uri.tryParse(href ?? '');
                    if (uri == null ||
                        !['https', 'http'].contains(uri.scheme) ||
                        uri.host.isEmpty) return;
                    try {
                      final opened = await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                      if (!opened && mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Could not open this link.')));
                    } catch (_) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Could not open this link.')));
                    }
                  },
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: T.body
                        .copyWith(color: Bold.inkOf(context), height: 1.55),
                    strong: const TextStyle(fontWeight: FontWeight.w700),
                    h1: T.title.copyWith(color: Bold.inkOf(context)),
                    h2: T.heading.copyWith(color: Bold.inkOf(context)),
                    h3: T.heading.copyWith(color: Bold.inkOf(context)),
                    a: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline),
                    code: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Bold.inkOf(context)),
                    codeblockDecoration: BoxDecoration(
                        color: Bold.canvasOf(context),
                        borderRadius: BorderRadius.circular(8)),
                    blockquoteDecoration: BoxDecoration(
                        color: Bold.canvasOf(context),
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ])),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.sizeOf(context).width < 800 ? 90.0 : 0.0;
    return Scaffold(
      appBar: AppBar(title: Text('AI space', style: T.title), actions: [
        IconButton(
            tooltip: 'Conversation history',
            onPressed: _sending || _loading ? null : _history,
            icon: const Icon(Icons.history)),
        IconButton(
            tooltip: 'New conversation',
            onPressed: _sending ? null : _new,
            icon: const Icon(Icons.edit_square)),
      ]),
      body: SafeArea(
          top: false,
          child: Padding(
              padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.viewInsetsOf(context).bottom > 0 ? 0 : bottom),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                      initialValue: _subjectId ?? '',
                                      key: ValueKey(
                                          '${_space?['id']}-$_subjectId'),
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Conversation context',
                                          border: OutlineInputBorder()),
                                      items: [
                                        if (_subjectId != null &&
                                            !_subjects.any(
                                                (s) => s['id'] == _subjectId))
                                          DropdownMenuItem(
                                              value: _subjectId,
                                              child: const Text(
                                                  'Notes · unavailable subject')),
                                        const DropdownMenuItem(
                                            value: '',
                                            child: Text('General knowledge')),
                                        ..._subjects.map((s) =>
                                            DropdownMenuItem(
                                                value: s['id'] as String,
                                                child: Text(
                                                    'Notes · ${s['name']}',
                                                    overflow:
                                                        TextOverflow.ellipsis)))
                                      ],
                                      onChanged: _space != null || _sending
                                          ? null
                                          : (v) => setState(() =>
                                              _subjectId = v == '' ? null : v)),
                                  const SizedBox(height: 8),
                                  Text(
                                      _subjectId == null
                                          ? 'Model knowledge · no live web search. Check important facts.'
                                          : 'Matching excerpts from processed notes + clearly labelled general knowledge.',
                                      style: T.small.copyWith(
                                          color: Bold.slateOf(context))),
                                ])),
                        Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : ListView(
                                    controller: _scroll,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    children: [
                                        if (_turns.isEmpty && !_sending) ...[
                                          const SizedBox(height: 32),
                                          Text(
                                              'A space to think things through.',
                                              style: T.display.copyWith(
                                                  color: Bold.inkOf(context))),
                                          const SizedBox(height: 12),
                                          Text(
                                              'Ask a question, explore an idea, or work through something difficult. Choose a subject above to bring your notes into the conversation.',
                                              style: T.body.copyWith(
                                                  color:
                                                      Bold.slateOf(context))),
                                          const SizedBox(height: 24),
                                          for (final prompt in [
                                            'Explain a difficult idea step by step',
                                            'Help me plan my revision',
                                            'Help me think through a problem'
                                          ])
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8),
                                                child: OutlinedButton(
                                                    onPressed: () => setState(
                                                        () => _input.text =
                                                            prompt),
                                                    child: Text(prompt))),
                                        ],
                                        for (final turn in _turns) ...[
                                          _message(turn['prompt'], user: true),
                                          _message(turn['reply'], user: false),
                                          if ((turn['sources'] as List? ?? [])
                                              .isNotEmpty)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 20),
                                                child: ExpansionTile(
                                                    title: const Text(
                                                        'Note excerpts used'),
                                                    children: [
                                                      for (final source
                                                          in turn['sources'])
                                                        ListTile(
                                                            title: Text(
                                                                '[${source['label']}] ${source['filename']}${source['page'] == null ? '' : ' · page ${source['page']}'}'),
                                                            subtitle:
                                                                SelectableText(
                                                                    source[
                                                                        'content']))
                                                    ])),
                                        ],
                                        if (_sending) ...[
                                          _message(_pendingText, user: true),
                                          Semantics(
                                              liveRegion: true,
                                              child: Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Row(children: [
                                                    SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth:
                                                                    2)),
                                                    SizedBox(width: 12),
                                                    Text('Thinking…')
                                                  ])))
                                        ]
                                      ])),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(_error!,
                                            style: T.small.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                    if (_spaces.isEmpty && _space == null)
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Reload'))
                                  ]))),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                      child: TextField(
                                          controller: _input,
                                          onChanged: (_) => setState(() {}),
                                          readOnly: _sending,
                                          maxLength: 6000,
                                          minLines: 1,
                                          maxLines: 5,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                              labelText: 'Message ViaX',
                                              hintText:
                                                  'Ask, explore, or explain…',
                                              border: OutlineInputBorder(),
                                              counterText: ''))),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                      tooltip: _sending
                                          ? 'Waiting for reply'
                                          : 'Send message',
                                      onPressed: _sending ||
                                              _loading ||
                                              _input.text.trim().isEmpty
                                          ? null
                                          : _send,
                                      icon: const Icon(Icons.arrow_upward),
                                      constraints: const BoxConstraints(
                                          minWidth: 48, minHeight: 48)),
                                ])),
                      ]))))),
    );
  }
}
