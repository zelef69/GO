import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'config/app_dependencies.dart';
import 'routes/app_routes.dart';

class GoPlayApp extends StatelessWidget {
  const GoPlayApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(dependencies: dependencies);
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE11D48)),
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.browser,
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}
