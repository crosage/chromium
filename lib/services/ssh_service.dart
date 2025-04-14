import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/command_log.dart';
class SSHService {
  static Future<CommandLog> execute({
    required String host,
    int port = 22,
    required String username,
    required String password,
    required String command,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final timestamp = DateTime.now();
    final logData = <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'type': CommandType.ssh.name,
      'host': host,
      'port': port,
      'user': username,
      'command': command,
      'stdout': '',
      'stderr': '',
      'exitCode': -99,
    };
    // trim移除开头和结尾的空格
    if (host.trim().isEmpty || username.trim().isEmpty || command.trim().isEmpty) {
      logData['stderr'] = '错误: 主机、用户名和命令不能为空。';
      logData['exitCode'] = -5;
      if (kDebugMode) print("SSH Input Error: ${logData['stderr']}");
      return CommandLog.fromMap(logData..update('exit_code', (val) => logData['exitCode']));
    }

    SSHClient? client;

    try {
      if (kDebugMode) print('SSH: 尝试连接到 $username@$host:$port...');
      final socket = await SSHSocket.connect(host, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () {
          if (kDebugMode) print('SSH: 提供密码 (长度: ${password.length})...');
          return password;
        },
        onAuthenticated: () {
          if (kDebugMode) print('SSH: 认证成功!');
        },
      );

      if (kDebugMode) print('SSH: 连接已建立。即将执行命令: $command');

      final session=await client.execute(command);
      
      final stdoutFuture=session.stdout.transform(utf8.decoder as StreamTransformer<Uint8List, dynamic>).join();
      final stderrFuture = session.stderr.transform(utf8.decoder as StreamTransformer<Uint8List, dynamic>).join();
      await session.done.timeout(timeout);
      logData['exitCode'] = session.exitCode ?? -1;
      logData['stdout'] = await stdoutFuture.timeout(const Duration(seconds: 10));
      logData['stderr'] = await stderrFuture.timeout(const Duration(seconds: 10));

      if (logData['exitCode'] != 0) {
        logData['stderr'] = (logData['stderr'] ?? '') + '(命令以非零状态 ${logData['exitCode']} 退出。错误信息可能在标准输出中。)';
        if (kDebugMode) print("SSH Command finished with non-zero exit code: ${logData['exitCode']}");
      } else {
        if (kDebugMode) print('SSH: 命令成功完成 (退出码 0)。');
      }

      // --- Error Handling ---
    } on TimeoutException catch (e) {
      logData['stderr'] = '错误: SSH 操作超时。\n${e.message ?? '未指定超时原因。'}';
      logData['exitCode'] = -6; // Specific code for timeout
      if (kDebugMode) print("SSH Timeout Error: ${logData['stderr']}");
    } on SSHError catch (e) {
      // Specific SSH protocol or authentication errors
      logData['stderr'] = '错误: SSH 操作失败。\n消息: ${e.toString()}\n';
      logData['exitCode'] = -3; // Specific code for SSH errors
      if (kDebugMode) print("SSH Error: ${logData['stderr']}");
    } on SocketException catch (e) {
      logData['stderr'] = '错误: 网络连接失败。\n消息: ${e.message}\n地址: ${e.address}:${e.port}';
      logData['exitCode'] = -7;
      if (kDebugMode) print("SSH Socket Error: ${logData['stderr']}");
    } catch (e) {
      logData['stderr'] = '错误: 执行 SSH 时发生未知异常。\n${e.toString()}';
      logData['exitCode'] = -4;
      if (kDebugMode) print("SSH General Error: ${logData['stderr']}");
    } finally {
      if (client != null) {
        try {
          client.close();
          if (kDebugMode) print('SSH: 连接已关闭。');
        } catch (e) {
          if (kDebugMode) print('SSH: 关闭连接时发生错误: $e');
          if (logData['stderr']!.isEmpty && logData['exitCode'] == -99) {
            logData['stderr'] = '关闭 SSH 连接时出错: ${e.toString()}';
            logData['exitCode'] = -8;
          }
        }
      }
    }

    final finalLogData = <String, dynamic>{
      'id': null,
      'timestamp': logData['timestamp'],
      'type': logData['type'],
      'host': logData['host'],
      'port': logData['port'],
      'user': logData['user'],
      'command': logData['command'],
      'stdout': logData['stdout'],
      'stderr': logData['stderr'],
      'exit_code': logData['exitCode'],
    };

    return CommandLog.fromMap(finalLogData);
  }
}