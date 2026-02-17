import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/coloring_page.dart';
import 'coloring_repository.dart';

class FirestoreColoringRepository implements ColoringRepository {
  final FirebaseFirestore _db;
  final String collectionPath;

  FirestoreColoringRepository({
    FirebaseFirestore? firestore,
    this.collectionPath = 'coloring_pages',
  }) : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<ColoringPage>> listPages({String? ageBand, String searchText = ''}) async {
    final snap = await _db.collection(collectionPath).get();
    final pages = snap.docs
        .map(_fromDoc)
        .where((p) => p != null)
        .cast<ColoringPage>()
        .toList();

    final q = searchText.trim().toLowerCase();
    final age = ageBand?.trim().toLowerCase();
    return pages.where((p) {
      final title = p.title.trim().toLowerCase();
      final pageAge = p.ageBand.trim().toLowerCase();
      final matchesSearch = q.isEmpty || title.contains(q) || p.id.toLowerCase().contains(q);
      final matchesAge = age == null || age.isEmpty || pageAge == age;
      return matchesSearch && matchesAge;
    }).toList();
  }

  @override
  Future<ColoringPage> getById(String id) async {
    final doc = await _db.collection(collectionPath).doc(id).get();
    if (doc.exists) {
      final page = _fromDoc(doc);
      if (page != null) return page;
    }

    // Fallback search if doc id and payload id differ.
    final snap = await _db.collection(collectionPath).where('id', isEqualTo: id).limit(1).get();
    if (snap.docs.isEmpty) {
      throw Exception('Coloring page not found: $id');
    }
    final page = _fromDoc(snap.docs.first);
    if (page == null) {
      throw Exception('Invalid coloring page data: $id');
    }
    return page;
  }

  ColoringPage? _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    final id = _string(data['id']) ?? doc.id;
    final title = _string(data['title']) ?? id;
    final ageBand = _string(data['ageBand']) ?? _string(data['age_band']) ?? '4-7';
    // Standardized Firestore schema:
    // - outlineUrl: outline image URL/path
    // - idMapUrl: id-map/mask image URL/path
    final imageAsset = _string(data['outlineURL']) ?? '';
    final maskAsset = _string(data['IdMapUrl']) ?? '';

    if (imageAsset.isEmpty || maskAsset.isEmpty) {
      if (kDebugMode) {
        debugPrint('FirestoreColoringRepository invalid doc ${doc.id}: missing image/mask');
      }
      return null;
    }

    return ColoringPage(
      id: id,
      title: title,
      ageBand: ageBand,
      imageAsset: imageAsset,
      maskAsset: maskAsset,
    );
  }

  String? _string(dynamic v) {
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    return null;
  }
}
