import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reading_progress.dart';
import '../models/story_progress.dart';
import 'progress_repository.dart';

class FirestoreProgressRepository implements ProgressRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreProgressRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String _uid() {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('Not signed in');
    }
    return u.uid;
  }

  DocumentReference<Map<String, dynamic>> _readingDoc() {
    final uid = _uid();
    // users/{uid}/progress/reading
    return _db.doc('users/$uid/progress/reading');
  }

  CollectionReference<Map<String, dynamic>> _storiesCol() {
    final uid = _uid();
    // users/{uid}/progress/stories/{storyId}
    return _db.collection('users/$uid/progress/stories');
  }

  // ---------------- ReadingProgress (global "last") ----------------

  @override
  Future<ReadingProgress?> getReadingProgress() async {
    final snap = await _readingDoc().get();
    if (!snap.exists) return null;

    final data = snap.data();
    if (data == null) return null;

    final storyId = (data['storyId'] as String?) ?? '';
    if (storyId.isEmpty) return null;

    final pageIndex = (data['pageIndex'] as num?)?.toInt() ?? 0;

    DateTime updatedAt;
    final ts = data['updatedAt'];
    if (ts is Timestamp) {
      updatedAt = ts.toDate();
    } else if (ts is String) {
      updatedAt = DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return ReadingProgress(
      storyId: storyId,
      pageIndex: pageIndex,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> saveReadingProgress(ReadingProgress progress) async {
    await _readingDoc().set({
      'storyId': progress.storyId,
      'pageIndex': progress.pageIndex,
      'updatedAt': FieldValue.serverTimestamp(), // server-authoritative
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearReadingProgress() async {
    await _readingDoc().delete();
  }

  // ---------------- StoryProgress (per story) ----------------

  @override
  Future<StoryProgress?> getStoryProgress(String storyId) async {
    final snap = await _storiesCol().doc(storyId).get();
    if (!snap.exists) return null;

    final data = snap.data();
    if (data == null) return null;

    final lastPageIndex = (data['lastPageIndex'] as num?)?.toInt() ?? 0;
    final completed = (data['completed'] as bool?) ?? false;

    DateTime lastOpenedAt;
    final ts = data['lastOpenedAt'];
    if (ts is Timestamp) {
      lastOpenedAt = ts.toDate();
    } else if (ts is String) {
      lastOpenedAt = DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      lastOpenedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return StoryProgress(
      storyId: storyId,
      lastPageIndex: lastPageIndex,
      completed: completed,
      lastOpenedAt: lastOpenedAt,
    );
  }

  @override
  Future<List<StoryProgress>> getAllStoryProgress() async {
    final qs = await _storiesCol().get();
    final out = <StoryProgress>[];

    for (final doc in qs.docs) {
      final data = doc.data();
      final storyId = doc.id;

      final lastPageIndex = (data['lastPageIndex'] as num?)?.toInt() ?? 0;
      final completed = (data['completed'] as bool?) ?? false;

      DateTime lastOpenedAt;
      final ts = data['lastOpenedAt'];
      if (ts is Timestamp) {
        lastOpenedAt = ts.toDate();
      } else if (ts is String) {
        lastOpenedAt = DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        lastOpenedAt = DateTime.fromMillisecondsSinceEpoch(0);
      }

      out.add(
        StoryProgress(
          storyId: storyId,
          lastPageIndex: lastPageIndex,
          completed: completed,
          lastOpenedAt: lastOpenedAt,
        ),
      );
    }

    out.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return out;
  }

  @override
  Future<void> saveStoryProgress(StoryProgress progress) async {
    await _storiesCol().doc(progress.storyId).set({
      'lastPageIndex': progress.lastPageIndex,
      'completed': progress.completed,
      'lastOpenedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
}
