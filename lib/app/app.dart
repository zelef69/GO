import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'config/setup_dependencies.dart';
import '../features/setup/presentation/setup_page.dart';

class GoPlayApp extends StatelessWidget {
  const GoPlayApp({required this.dependencies, super.key});

  final SetupDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE11D48)),
        useMaterial3: true,
      ),
      home: SetupPage(updateService: dependencies.updateService),
    );
  }
}
