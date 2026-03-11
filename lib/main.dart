import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/config/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = AppDependencies.create();
  runApp(GoPlayApp(dependencies: dependencies));
}
