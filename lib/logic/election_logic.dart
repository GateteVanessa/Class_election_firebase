import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/candidate.dart';

/// Lab 4: trim, collapse spaces, Title Case.
String cleanName(String raw) {
  return raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Percentage of all votes. Never divides by zero.
double percentOf(int votes, int totalVotes) {
  if (totalVotes == 0) return 0;
  return votes / totalVotes * 100;
}

/// Lab 9: highest votes first. Ties are ordered by name so the order is stable.
List<Candidate> rankCandidates(List<Candidate> list) {
  final ranked = List<Candidate>.from(list);
  ranked.sort((a, b) {
    final byVotes = b.votes.compareTo(a.votes); // more votes goes earlier
    if (byVotes != 0) return byVotes;
    return a.name.compareTo(b.name);
  });
  return ranked;
}

/// Lab 8: winner or tie, based on how many candidates share the top score.
String bannerText(List<Candidate> list) {
  final total = list.fold(0, (sum, c) => sum + c.votes);
  if (total == 0) return 'No votes yet';

  final top = list.map((c) => c.votes).reduce((a, b) => a > b ? a : b);
  final leaders = list.where((c) => c.votes == top).toList();

  if (leaders.length == 1) return 'Winner: ${leaders.first.name}';
  final names = leaders.map((c) => c.name).join(' and ');
  return 'Tie between $names ($top votes each)';
}

class VoteRecord {
  final String key; // the id of the voter's document in Firestore
  final String voter;
  final Candidate candidate;
  VoteRecord({required this.key, required this.voter, required this.candidate});
}

// A voter document, as read from Firestore.
class _VoterDoc {
  _VoterDoc(this.key, this.name, this.candidateId, this.createdAt);
  final String key;
  final String name;
  final String candidateId;
  final DateTime createdAt;
}

// The document id of a voter: the cleaned name in lowercase, made safe
// (a "/" is not allowed in an id). The same person gets the same id,
// so one person can only be in the voters collection once.
String voterKey(String cleanedName) {
  return 'v_${Uri.encodeComponent(cleanedName.toLowerCase())}';
}

DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
    FirebaseFirestore.instance.collection('users').doc(uid);

/// Sample data, written ONCE right after a new account is created.
Future<void> addSampleCandidates() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final root = _userDoc(uid);
  final batch = FirebaseFirestore.instance.batch();
  for (final name in ['Keza', 'Mutoni', 'Eric']) {
    batch.set(root.collection('candidates').doc(), {'name': name, 'votes': 0});
  }
  batch.set(root.collection('settings').doc('election'), {'classSize': 30});
  await batch.commit();
}

/// Holds all the data of ONE logged-in user. Screens listen to it.
///
/// The data now lives in Firestore under users/{uid}/:
///   candidates/{id}  -> name, votes
///   voters/{key}     -> name, candidateId, createdAt
///   settings/election -> classSize
/// Election listens to these three places (snapshots). Every change, from
/// this phone or from the console, arrives by itself and the screens update.
class Election extends ChangeNotifier {
  Election(this.uid);

  final String uid;

  // Same names as before, so the three screens do not change.
  final List<Candidate> candidates = [];
  final List<String> voters = [];
  final List<VoteRecord> voteHistory = [];
  int classSize = 30;

  /// Set when Firestore refuses to read (for example permission-denied).
  String? loadError;

  String? _writeError;
  final List<_VoterDoc> _voterDocs = [];
  final Set<String> _inFlight = {}; // voters being saved right now
  StreamSubscription<dynamic>? _candidatesSub;
  StreamSubscription<dynamic>? _votersSub;
  StreamSubscription<dynamic>? _settingsSub;
  bool _disposed = false;

  DocumentReference<Map<String, dynamic>> get _root => _userDoc(uid);
  CollectionReference<Map<String, dynamic>> get _candidatesRef =>
      _root.collection('candidates');
  CollectionReference<Map<String, dynamic>> get _votersRef =>
      _root.collection('voters');
  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _root.collection('settings').doc('election');

  int get totalVotes => voters.length;

  bool hasVoted(String cleaned) =>
      voters.contains(cleaned) || _inFlight.contains(voterKey(cleaned));

  /// The screen shows this message once, then it is cleared.
  String? takeWriteError() {
    final e = _writeError;
    _writeError = null;
    return e;
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _candidatesSub?.cancel();
    _votersSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  // ---------------- reading: live from Firestore ----------------

  /// Starts listening. Finishes when the first data of all three places
  /// has arrived (or the server refused / did not answer).
  Future<void> start() async {
    final first = <Completer<void>>[
      Completer<void>(),
      Completer<void>(),
      Completer<void>(),
    ];
    void done(int i) {
      if (!first[i].isCompleted) first[i].complete();
    }

    void fail(int i, Object e) {
      loadError = _friendly(e);
      notifyListeners();
      done(i);
    }

    _candidatesSub = _candidatesRef.orderBy('name').snapshots().listen((snap) {
      candidates
        ..clear()
        ..addAll(snap.docs.map(Candidate.fromDoc));
      loadError = null;
      _rebuildHistory();
      notifyListeners();
      done(0);
    }, onError: (Object e) => fail(0, e));

    _votersSub = _votersRef.snapshots().listen((snap) {
      _voterDocs
        ..clear()
        ..addAll(snap.docs.map((d) {
          final data = d.data();
          // A vote that is still being written has no time yet: it is the newest.
          final ts = data['createdAt'] as Timestamp?;
          return _VoterDoc(
            d.id,
            data['name'] as String,
            data['candidateId'] as String? ?? '',
            ts?.toDate() ?? DateTime.now(),
          );
        }));
      _voterDocs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _rebuildHistory();
      notifyListeners();
      done(1);
    }, onError: (Object e) => fail(1, e));

    _settingsSub = _settingsRef.snapshots().listen((snap) {
      classSize = (snap.data()?['classSize'] as num?)?.toInt() ?? 30;
      notifyListeners();
      done(2);
    }, onError: (Object e) => fail(2, e));

    try {
      await Future.wait(first.map((c) => c.future))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      loadError =
      'The server did not answer. Check your internet connection.';
      notifyListeners();
    }
  }

  // voters and voteHistory are made from the voter documents,
  // oldest first, so the last one is the last vote (for Undo).
  void _rebuildHistory() {
    voters
      ..clear()
      ..addAll(_voterDocs.map((v) => v.name));
    voteHistory.clear();
    for (final v in _voterDocs) {
      final matches = candidates.where((c) => c.id == v.candidateId);
      if (matches.isNotEmpty) {
        voteHistory.add(
          VoteRecord(key: v.key, voter: v.name, candidate: matches.first),
        );
      }
    }
  }

  String _friendly(Object e) {
    if (e is FirebaseException) return '[${e.plugin}/${e.code}] ${e.message ?? ''}';
    return e.toString();
  }

  // ---------------- writing: to Firestore ----------------

  // Start a write. If the server refuses, the screen shows a message.
  void _run(Future<void> write, {String? lockKey}) {
    write.catchError((Object e) {
      _writeError = 'Could not save: ${_friendly(e)}';
      notifyListeners();
    }).whenComplete(() {
      if (lockKey != null) _inFlight.remove(lockKey);
    });
  }

  Future<void> _commitInChunks(List<void Function(WriteBatch)> ops) async {
    // A batch holds at most 500 writes.
    for (var i = 0; i < ops.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final op in ops.skip(i).take(400)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  void setClassSize(int size) {
    classSize = size < 0 ? 0 : size;
    notifyListeners();
    _run(_settingsRef.set({'classSize': classSize}));
  }

  /// Returns an error message, or null if the vote was counted.
  String? castVote(String rawName, Candidate candidate) {
    final voter = cleanName(rawName);
    if (voter.isEmpty) return 'Please type your name';
    if (hasVoted(voter)) return '$voter has already voted';

    final key = voterKey(voter);
    _inFlight.add(key);

    // +1 on the candidate AND the voter is recorded: all of it, or none.
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_candidatesRef.doc(candidate.id),
        {'votes': FieldValue.increment(1)});
    batch.set(_votersRef.doc(key), {
      'name': voter,
      'candidateId': candidate.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _run(batch.commit(), lockKey: key);
    return null;
  }

  /// Undo the last cast vote.
  String? undoLastVote() {
    if (voteHistory.isEmpty) return 'No votes to undo';
    final last = voteHistory.last;
    if (_inFlight.contains(last.key)) return 'Please wait a moment';
    _inFlight.add(last.key);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(_candidatesRef.doc(last.candidate.id),
        {'votes': FieldValue.increment(-1)});
    batch.delete(_votersRef.doc(last.key));
    _run(batch.commit(), lockKey: last.key);
    return null;
  }

  /// Returns an error message, or null if the candidate was added.
  String? addCandidate(String rawName) {
    final name = cleanName(rawName);
    if (name.isEmpty) return 'Candidate name cannot be empty';
    if (candidates.any((c) => c.name == name)) return '$name already exists';

    _run(_candidatesRef.add(Candidate(name: name).toMap()));
    return null;
  }

  /// Edit: change the name of a candidate (update). Votes stay, because
  /// voters point to the candidate's id, not to the name.
  String? renameCandidate(Candidate c, String rawName) {
    final name = cleanName(rawName);
    if (name.isEmpty) return 'Candidate name cannot be empty';
    if (name == c.name) return null;
    if (candidates.any((x) => x.name == name)) return '$name already exists';
    _run(_candidatesRef.doc(c.id).update({'name': name}));
    return null;
  }

  /// Returns an error message, or null if the candidate was removed.
  String? removeCandidate(Candidate c) {
    if (c.votes > 0) return '${c.name} has votes and cannot be removed';
    _run(_candidatesRef.doc(c.id).delete());
    return null;
  }

  void reset() {
    final ops = <void Function(WriteBatch)>[];
    for (final c in candidates) {
      ops.add((b) => b.update(_candidatesRef.doc(c.id), {'votes': 0}));
    }
    for (final v in _voterDocs) {
      ops.add((b) => b.delete(_votersRef.doc(v.key)));
    }
    _run(_commitInChunks(ops));
  }
}