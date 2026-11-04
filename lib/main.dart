import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'services/app_state.dart';
import 'services/native_companion.dart';
import 'services/saved_page.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'l10n/l10n.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GopherApp(initialUrl: arguments.isEmpty ? null : arguments.first));
}

class GopherApp extends StatelessWidget {
  final String? initialUrl;
  const GopherApp({super.key, this.initialUrl});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final state = AppState()..init();
        if (initialUrl != null) state.navigate(SavedPage.opening(initialUrl!));
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
          const MethodChannel(
            'org.gopherclient/navigation',
          ).setMethodCallHandler((call) async {
            if (call.method == 'openUrl' && call.arguments is String) {
              state.selectTab(0);
              await state.openFromOutside(call.arguments as String);
            }
          });
          const MethodChannel(
            'org.gopherclient/navigation',
          ).invokeMethod<void>('ready').catchError((Object _) {});
          // Reopen a previously enabled library so its bookmarks remain usable.
          NativeCompanion.resume().catchError((Object _) {});
        }
        return state;
      },
      child: MaterialApp(
        title: 'AI-2 Gopher',
        theme: readerTheme,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
