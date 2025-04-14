import 'package:flutter/material.dart';
import 'package:powerdealer/services/database.dart';
import 'package:powerdealer/ui/pages/home_screen.dart';
import 'package:provider/provider.dart';
import 'services/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'ui/pages/home_screen.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  try {
    await DatabaseService().database;
    print("数据库服务已准备就绪");
  } catch (e) {
    print("!!! 数据库初始化失败，应用可能无法正常工作: $e");
  }
  runApp(
    Provider<DatabaseService>(
      create: (_) => DatabaseService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '命令执行与日志',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        )
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}