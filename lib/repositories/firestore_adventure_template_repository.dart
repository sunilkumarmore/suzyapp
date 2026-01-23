import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/adventure_template.dart';
import 'adventure_template_repository.dart';

class FirestoreAdventureTemplateRepository implements AdventureTemplateRepository {
  final FirebaseFirestore _db;

  FirestoreAdventureTemplateRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<AdventureTemplate>> loadTemplates() async {
    final snap = await _db.collection('adventure_templates').get();
    return snap.docs
        .map(_fromDoc)
        .where((t) => t != null)
        .cast<AdventureTemplate>()
        .toList();
  }

  AdventureTemplate? _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    final map = Map<String, dynamic>.from(data);
    map['id'] ??= doc.id;

    try {
      return AdventureTemplate.fromJson(map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FirestoreAdventureTemplateRepository invalid doc ${doc.id}: $e');
      }
      return null;
    }
  }
}
