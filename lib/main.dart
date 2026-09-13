import 'package:flutter/material.dart';

import 'app.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.initialize();
  runApp(const JaleRoot());
}
