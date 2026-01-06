import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:suzyapp/screens/create_adventure_screen.dart';
import 'firebase_options.dart';

import 'design_system/app_theme.dart';
// ignore if already in this file

import 'repositories/mock_story_repository.dart';
import 'repositories/story_repository.dart';
import 'repositories/mock_progress_repository.dart';
import 'repositories/progress_repository.dart';

import 'screens/home_screen.dart';
import 'screens/story_library_screen.dart';
import 'screens/story_reader_screen.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/story_completion_screen.dart';
import 'screens/parent_summary_screen.dart';
import 'repositories/asset_adventure_template_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

Future<void> main() async {
  
 
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);



  final StoryRepository storyRepo = MockStoryRepository();
  final ProgressRepository progressRepo = MockProgressRepository();


  await ensureDevAuth(); // ✅ stable UID
final u = FirebaseAuth.instance.currentUser;
debugPrint('AUTH user: uid=${u?.uid} email=${u?.email} anon=${u?.isAnonymous}');
  runApp(SuzyApp(storyRepository: storyRepo, progressRepository: progressRepo));
}


Future<void> ensureDevAuth() async {
  if (!kDebugMode) return; // ⛔ never runs in release

  const email = 'shivaji@suzyapp.local';
  const password = 'DevPassword123!';

  final auth = FirebaseAuth.instance;

  // Already signed in as dev
  if (auth.currentUser?.email == email) return;

  try {
    await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  } catch (_) {
    // First time only
    await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

class SuzyApp extends StatelessWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;

  const SuzyApp({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
  });


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuzyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routes: {
        
'/': (_) => HomeScreen(
      storyRepository: storyRepository,
      progressRepository: progressRepository,
),
    '/create': (_) => CreateAdventureScreen(
          templateRepository: AssetAdventureTemplateRepository(),
          progressRepository: progressRepository,
        ),
    '/parent-summary': (_) =>
        ParentSummaryScreen(progressRepository: progressRepository),
       '/library': (_) => StoryLibraryScreen(
  storyRepository: storyRepository,
  progressRepository: progressRepository,
),
        '/reader': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as StoryReaderArgs;
          return StoryReaderScreen(
            storyRepository: storyRepository,
            progressRepository: progressRepository,
            storyId: args.storyId,
            startPageIndex: args.startPageIndex, );
        },
        '/complete': (ctx) {
  final args = ModalRoute.of(ctx)!.settings.arguments as StoryCompletionArgs;
  return StoryCompletionScreen(args: args);
},
        // keep if you want, but hide in UI
        '/firebase-test': (_) => const FirebaseTestScreen(),
      },
    );
  }
}
Future<void> ensureAnonAuth() async {
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }
}

class StoryReaderArgs {
  final String storyId;
  final int? startPageIndex;
  StoryReaderArgs(this.storyId, {this.startPageIndex});
}
