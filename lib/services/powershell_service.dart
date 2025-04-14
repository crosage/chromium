import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/command_log.dart';


class PowerShellService {
  static Future<CommandLog> execute(
      String command, {
        Duration timeout = const Duration(minutes: 5),
        String? workingDirectory,
      }) async {

    final timestamp = DateTime.now();
    final logData = <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'type': CommandType.powershell.name,
      'host': null,
      'port': null,
      'user': null,
      'command': command,
      'stdout': '',
      'stderr': '',
      'exit_code': -99,
    };

    if (!Platform.isWindows) {
      logData['stderr'] = '错误: PowerShell 执行仅在 Windows 上受支持。';
      logData['exit_code'] = -1;
      if (kDebugMode) print("PowerShell Platform Error: ${logData['stderr']}");
      return CommandLog.fromMap(logData);
    }
    if (command.trim().isEmpty) {
      logData['stderr'] = '错误: 执行的命令不能为空。';
      logData['exit_code'] = -5;
      if (kDebugMode) print("PowerShell Input Error: ${logData['stderr']}");
      return CommandLog.fromMap(logData);
    }

    try {
      if (kDebugMode) {
        print("执行 PowerShell: powershell.exe -NoProfile -NonInteractive -Command \"$command\"");
        if (workingDirectory != null) {
          print("  工作目录: $workingDirectory");
        }
      }

      final processResult = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', command],
        workingDirectory: workingDirectory,
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      print("退出码为${processResult.exitCode}");
      logData['stdout'] = processResult.stdout as String? ?? '';
      logData['stderr'] = processResult.stderr as String? ?? '';

      logData['exit_code'] = processResult.exitCode;
      print("退出码为${processResult.exitCode}  赋值后${processResult.exitCode}");
      if (kDebugMode) {
        print("PowerShell 退出码: ${logData['exit_code']}");
        if (logData['stdout']!.isNotEmpty) print("PowerShell Stdout:\n${logData['stdout']}");
        if (logData['stderr']!.isNotEmpty) print("PowerShell Stderr:\n${logData['stderr']}");
      }

      if (logData['exit_code'] != 0 && logData['stderr']!.isEmpty) {
        logData['stderr'] = '(命令以非零状态 ${logData['exit_code']} 退出，但标准错误无输出。)';
      } else if (logData['exit_code'] != 0 && logData['stderr']!.isNotEmpty) {
        logData['stderr'] = (logData['stderr'] ?? '') + '\n(命令以非零状态 ${logData['exit_code']} 退出。)';
      }

    } on TimeoutException catch (e) {
      logData['stderr'] = '错误: PowerShell 命令执行超时 (${timeout.inSeconds} 秒)。\n${e.message ?? ''}';
      logData['exit_code'] = -6;
      if (kDebugMode) print("PowerShell Timeout Error: ${logData['stderr']}");
    } on ProcessException catch (e) {
      logData['stderr'] = '错误: 执行 PowerShell 进程时出错。\n消息: ${e.message}\n代码: ${e.errorCode}\n参数: ${e.arguments}';
      logData['exit_code'] = -2;
      if (kDebugMode) print("PowerShell Process Error: ${logData['stderr']}");
    } catch (e) {
      logData['stderr'] = '错误: 执行 PowerShell 时发生未知异常。\n${e.toString()}';
      logData['exit_code'] = -4;
      if (kDebugMode) print("PowerShell General Error: ${logData['stderr']}");
    }
    return CommandLog.fromMap(logData);
  }
}