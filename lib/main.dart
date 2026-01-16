import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:suzyapp/repositories/firestore_progress_repository.dart';
import 'package:suzyapp/screens/privacy_policy_screen.dart';

import 'firebase_options.dart';

import 'design_system/app_theme.dart';

import 'repositories/story_repository.dart';
import 'repositories/mock_story_repository.dart';
import 'repositories/firestore_story_repository.dart';
import 'repositories/composite_story_repository.dart';

import 'repositories/progress_repository.dart';
import 'repositories/composite_progress_repository.dart';
import 'repositories/local_progress_repository.dart';
import 'repositories/mock_progress_repository.dart';

import 'repositories/asset_adventure_template_repository.dart';
import 'repositories/parent_voice_settings_repository.dart';

import 'screens/home_screen.dart';
import 'screens/story_library_screen.dart';
import 'screens/story_reader_screen.dart';
import 'screens/story_completion_screen.dart';
import 'screens/parent_summary_screen.dart';
import 'screens/parent_voice_settings_screen.dart';
import 'screens/create_adventure_screen.dart';
import 'screens/firebase_test_screen.dart';

import 'services/parent_gate_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ---------- Repositories ----------
  final StoryRepository storyRepo = CompositeStoryRepository(
    primary: FirestoreStoryRepository(),
    fallback: MockStoryRepository(),
  );

  // final ProgressRepository progressRepo = CompositeProgressRepository(
  //   local: LocalProgressRepository(),
  //   cloud: MockProgressRepository(), // swap later with FirestoreProgressRepository
  // );

  final ProgressRepository progressRepo = CompositeProgressRepository(
  local: LocalProgressRepository(),
  cloud: FirestoreProgressRepository(),
);

  // ---------- Auth ----------
 // await configureAuthPersistenceForWeb();
   // await ensureAnonAuth();
  await ensureDevAuth(); //disable for production

  // ---------- Parent voice defaults ----------
  await ParentVoiceSettingsRepository().ensureDefaults();

  final u = FirebaseAuth.instance.currentUser;
  debugPrint(
    'AUTH user: uid=${u?.uid} email=${u?.email} anon=${u?.isAnonymous}',
  );

  runApp(
    SuzyApp(
      storyRepository: storyRepo,
      progressRepository: progressRepo,
    ),
  );
}

// ================== AUTH HELPERS ==================

Future<void> ensureAnonAuth() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    if (kDebugMode) {
      debugPrint('AUTH already signed in uid=${auth.currentUser!.uid}');
    }
    return;
  }

  final cred = await auth.signInAnonymously();

  if (kDebugMode) {
    debugPrint('AUTH anonymous uid=${cred.user?.uid}');
  }
}

Future<void> configureAuthPersistenceForWeb() async {
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
}

// ================== APP ROOT ==================

class SuzyApp extends StatefulWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;

  const SuzyApp({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
  });

  @override
  State<SuzyApp> createState() => _SuzyAppState();
}

class _SuzyAppState extends State<SuzyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 🔐 STEP 4 — Lock Parent Gate when app backgrounds
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ParentGateService.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuzyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routes: {
        '/': (_) => HomeScreen(
              storyRepository: widget.storyRepository,
              progressRepository: widget.progressRepository,
            ),

        '/library': (_) => StoryLibraryScreen(
              storyRepository: widget.storyRepository,
              progressRepository: widget.progressRepository,
            ),

'/privacy': (_) => const PrivacyPolicyScreen(),
        '/reader': (ctx) {
          final args =
              ModalRoute.of(ctx)!.settings.arguments as StoryReaderArgs;
          return StoryReaderScreen(
            storyRepository: widget.storyRepository,
            progressRepository: widget.progressRepository,
            storyId: args.storyId,
            startPageIndex: args.startPageIndex,
          );
        },

        '/complete': (ctx) {
          final args =
              ModalRoute.of(ctx)!.settings.arguments as StoryCompletionArgs;
          return StoryCompletionScreen(args: args);
        },

        // 🔐 Parent-gated screens (gate applied at navigation points)
        '/parent-summary': (_) =>
            ParentSummaryScreen(progressRepository: widget.progressRepository),

        '/parent-voice': (_) => const ParentVoiceSettingsScreen(),

        '/create': (_) => CreateAdventureScreen(
              templateRepository: AssetAdventureTemplateRepository(),
              progressRepository: widget.progressRepository,
            ),

        // Dev only
        '/firebase-test': (_) => const FirebaseTestScreen(),
      },
    );
  }
}



Future<void> ensureDevAuth() async {
  if (!kDebugMode) return; // ⛔ never runs in release

  const email = 'dev@suzyapp.local';
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

// ================== NAV ARGS ==================

class StoryReaderArgs {
  final String storyId;
  final int? startPageIndex;

  StoryReaderArgs(
    this.storyId, {
    this.startPageIndex,
  });
}
