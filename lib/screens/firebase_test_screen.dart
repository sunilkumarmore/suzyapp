import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FirebaseTestScreen extends StatefulWidget {
  const FirebaseTestScreen({super.key});

  @override
  State<FirebaseTestScreen> createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  String _status = 'Ready';

  Future<void> _runTest() async {
    setState(() => _status = 'Signing in anonymously…');

    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user!.uid;

    setState(() => _status = 'Writing Firestore doc…');
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    await ref.set({
      'ping': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': 'web',
    }, SetOptions(merge: true));

    setState(() => _status = 'Reading back…');
    final snap = await ref.get();

    setState(() => _status = '✅ Success! uid=$uid data=${snap.data()}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase Smoke Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _runTest,
              child: const Text('Run test (Auth + Firestore)'),
            ),
          ],
        ),
      ),
    );
  }
}
