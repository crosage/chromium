import "dart:async";
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/command_log.dart';
import 'config.dart';

class DatabaseService{
  static final DatabaseService _instance=DatabaseService._internal();
  factory DatabaseService() => _instance;
  //命名构造函数（如var user1 = User.fromJson(userData);），这里用私有命名构造函数，
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async{
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    try {
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, db);
      print("数据库路径: $path");

      return await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );
    } catch (e) {
      print("数据库初始化失败: $e");
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $logTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          type TEXT NOT NULL,
          host TEXT,
          port INTEGER,
          user TEXT,
          command TEXT NOT NULL,
          stdout TEXT,
          stderr TEXT,
          exit_code INTEGER NOT NULL
        )
      ''');
      print("数据库表 '$logTableName' 已创建");
    } catch (e) {
      print("创建表 '$logTableName' 失败: $e");
    }
  }

  Future<int> addLog(CommandLog log) async {
    final db = await database;
    // 移除 map 中的 null ID，让数据库自动生成
    final map = log.toMap();
    map.remove('id');
    return await db.insert(logTableName, map);
  }

  Future<CommandLog?> getLogById(int id) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return CommandLog.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print("根据 ID $id 获取日志失败: $e");
      return null;
    }
  }

  Future<List<CommandLog>> getAllLogs({int? limit, int? offset}) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );
      return List.generate(maps.length, (i) => CommandLog.fromMap(maps[i]));
    } catch (e) {
      print("获取所有日志失败: $e");
      return [];
    }
  }

  Future<int> deleteLog(int id) async {
    try {
      final db = await database;
      return await db.delete(
        logTableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print("删除日志 ID $id 失败: $e");
      return 0;
    }
  }

  Future<int> deleteAllLogs() async {
    try {
      final db = await database;
      int count = await db.delete(logTableName);
      print("已删除 $count 条日志记录");
      return count;
    } catch (e) {
      print("删除所有日志失败: $e");
      return 0;
    }
  }

  Future<List<CommandLog>> getLogsByDateRange(String startDate, String endDate) async {
    try {
      final db = await database;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(startDate) ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(endDate)) {
        print("错误: getLogsByDateRange 的日期格式无效: $startDate, $endDate");
        return [];
      }
      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        where: 'date(timestamp) BETWEEN ? AND ?',
        whereArgs: [startDate, endDate],
        orderBy: 'timestamp DESC',
      );
      return List.generate(maps.length, (i) => CommandLog.fromMap(maps[i]));
    } catch (e) {
      print("按日期范围 '$startDate' - '$endDate' 获取日志失败: $e");
      return [];
    }
  }

  Future<List<CommandLog>> searchLogs(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    try {
      final db = await database;
      final String pattern = '%$keyword%';
      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        where: 'command LIKE ? OR stdout LIKE ? OR stderr LIKE ?',
        whereArgs: [pattern, pattern, pattern],
        orderBy: 'timestamp DESC',
      );
      return List.generate(maps.length, (i) => CommandLog.fromMap(maps[i]));
    } catch (e) {
      print("搜索关键字 '$keyword' 失败: $e");
      return [];
    }
  }

  Future<List<CommandLog>> searchLogsByDateAndKeyword(String startDate, String endDate, String keyword) async {
    if (keyword.trim().isEmpty) return getLogsByDateRange(startDate,endDate); // If no keyword, just filter by date
    try {
      final db = await database;
      final String pattern = '%$keyword%';

      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        where: 'date(timestamp) BETWEEN ? AND ? AND (command LIKE ? OR stdout LIKE ? OR stderr LIKE ?)',
        whereArgs: [startDate,endDate, pattern, pattern, pattern],
        orderBy: 'timestamp DESC',
      );
      return List.generate(maps.length, (i) => CommandLog.fromMap(maps[i]));
    } catch (e) {
      print("按日期 '$startDate $endDate' 和关键字 '$keyword' 搜索日志失败: $e");
      return [];
    }
  }

  Future<List<String>> getDistinctCommandHistory({int limit = 100}) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        logTableName,
        distinct: true,
        columns: ['command'],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return maps.map((map) => map['command'] as String).toList();
    } catch (e) {
      print("获取去重命令历史失败: $e");
      return [];
    }
  }

  Future<void> close() async {
    try {
      final db = await database;
      await db.close();
      _database = null; // Reset the static variable
      print("数据库连接已关闭");
    } catch (e) {
      print("关闭数据库失败: $e");
    }
  }
}