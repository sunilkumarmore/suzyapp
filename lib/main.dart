import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Firebase & Theme
import 'firebase_options.dart';
import 'design_system/app_theme.dart';

// Repositories
import 'repositories/story_repository.dart';
import 'repositories/mock_story_repository.dart';
import 'repositories/firestore_story_repository.dart';
import 'repositories/composite_story_repository.dart';
import 'repositories/progress_repository.dart';
import 'repositories/composite_progress_repository.dart';
import 'repositories/local_progress_repository.dart';
import 'repositories/mock_progress_repository.dart';
import 'repositories/firestore_progress_repository.dart';
import 'repositories/asset_adventure_template_repository.dart';
import 'repositories/adventure_template_repository.dart';
import 'repositories/composite_adventure_template_repository.dart';
import 'repositories/firestore_adventure_template_repository.dart';
import 'repositories/parent_voice_settings_repository.dart';
import 'repositories/coloring_repository.dart';
import 'repositories/asset_coloring_repository.dart';

// Screens
import 'screens/home_screen.dart';
import 'screens/story_library_screen.dart';
import 'screens/story_reader_screen.dart';
import 'screens/story_completion_screen.dart';
import 'screens/parent_summary_screen.dart';
import 'screens/parent_voice_settings_screen.dart';
import 'screens/create_adventure_screen.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/coloring_library_screen.dart';
import 'screens/coloring_canvas_screen.dart';

// Services
import 'services/parent_gate_service.dart';


Future<void> main() async {
  // 1. Initialize Flutter Bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Immediate UI Launch (Kills White Screen on iOS 26)
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Starting SuzyApp...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    // 3. Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 4. SIGN IN FIRST (Crucial for ParentVoiceSettingsRepository)
    if (kIsWeb) {
      await configureAuthPersistenceForWeb();
    }
    await ensureAnonAuth();
   // await ensureDevAuth();

    // 5. Verify Auth State & Setup Defaults
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint('AUTH verified: ${user.uid}');
      // Only call this once we are SURE a user exists to avoid "Bad state"
      await ParentVoiceSettingsRepository().ensureDefaults();
    } else {
      debugPrint('AUTH WARNING: No user found after sign-in.');
    }

    // 6. Setup Repositories
    final StoryRepository storyRepo = CompositeStoryRepository(
      primary: FirestoreStoryRepository(),
      fallback: MockStoryRepository(),
    );

    final AdventureTemplateRepository templateRepo =
        CompositeAdventureTemplateRepository(
      primary: FirestoreAdventureTemplateRepository(),
      fallback: AssetAdventureTemplateRepository(),
    );

    final ProgressRepository progressRepo = CompositeProgressRepository(
      local: LocalProgressRepository(),
      cloud: FirestoreProgressRepository(),
    );

    final ColoringRepository coloringRepo = AssetColoringRepository();

    // 7. Launch the actual App
    runApp(
      SuzyApp(
        storyRepository: storyRepo,
        progressRepository: progressRepo,
        adventureTemplateRepository: templateRepo,
        coloringRepository: coloringRepo,
      ),
    );
  } catch (e) {
    debugPrint("❌ CRITICAL BOOT ERROR: $e");
    // Show error on phone screen so it doesn't stay stuck on spinner
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Error: $e")))));
  }
}

// ================== AUTH HELPERS ==================

Future<void> ensureDevAuth() async {
  if (!kDebugMode) return; 

  const email = 'dev@suzyapp.local';
  const password = 'DevPassword123!';
  final auth = FirebaseAuth.instance;

  if (auth.currentUser?.email == email) return;

  try {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  } catch (_) {
    await auth.createUserWithEmailAndPassword(email: email, password: password);
  }
}

// ================== APP ROOT ==================

class SuzyApp extends StatefulWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;
  final AdventureTemplateRepository adventureTemplateRepository;
  final ColoringRepository coloringRepository;

  const SuzyApp({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
    required this.adventureTemplateRepository,
    required this.coloringRepository,
  });

  @override
  State<SuzyApp> createState() => _SuzyAppState();
}

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
FirebaseAuth.instance.authStateChanges().listen((User? user) {
  if (user == null) {
    print('User is currently signed out!');
  } else {
    print('User is signed in!');
  }
});
}
class _SuzyAppState extends State<SuzyApp> with WidgetsBindingObserver {
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
          final args = ModalRoute.of(ctx)!.settings.arguments as StoryReaderArgs;
          return StoryReaderScreen(
            storyRepository: widget.storyRepository,
            progressRepository: widget.progressRepository,
            storyId: args.storyId,
            startPageIndex: args.startPageIndex,
          );
        },
        '/complete': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as StoryCompletionArgs;
          return StoryCompletionScreen(args: args);
        },
        '/parent-summary': (_) =>
            ParentSummaryScreen(progressRepository: widget.progressRepository),
        '/parent-voice': (_) => const ParentVoiceSettingsScreen(),
        '/create': (_) => CreateAdventureScreen(
              templateRepository: widget.adventureTemplateRepository,
              progressRepository: widget.progressRepository,
            ),
        '/coloring': (_) => ColoringLibraryScreen(
              coloringRepository: widget.coloringRepository,
            ),
        '/coloring-canvas': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as ColoringCanvasArgs;
          return ColoringCanvasScreen(
            pages: args.pages,
            initialIndex: args.initialIndex,
          );
        },
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
