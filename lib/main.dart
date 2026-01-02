import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:suzyapp/repositories/adventure_template_repository.dart';
import 'package:suzyapp/screens/create_adventure_screen.dart';
import 'firebase_options.dart';

import 'design_system/app_theme.dart';
import 'main.dart' show StoryReaderArgs; // ignore if already in this file

import 'repositories/mock_story_repository.dart';
import 'repositories/story_repository.dart';
import 'repositories/mock_progress_repository.dart';
import 'repositories/progress_repository.dart';

import 'screens/home_screen.dart';
import 'screens/story_library_screen.dart';
import 'screens/story_reader_screen.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/story_completion_screen.dart';
import 'screens/parent_gate_screen.dart';
import 'screens/parent_summary_screen.dart';
import 'repositories/asset_adventure_template_repository.dart';
import 'screens/create_adventure_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final StoryRepository storyRepo = MockStoryRepository();
  final ProgressRepository progressRepo = MockProgressRepository();

  runApp(SuzyApp(storyRepository: storyRepo, progressRepository: progressRepo));
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
            startPageIndex: args.startPageIndex,
          );
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

class StoryReaderArgs {
  final String storyId;
  final int? startPageIndex;
  StoryReaderArgs(this.storyId, {this.startPageIndex});
}
