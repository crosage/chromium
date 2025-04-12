import 'package:intl/intl.dart'; // 用于日期格式化

enum CommandType { powershell, ssh }

class CommandLog {
  final int? id;
  final DateTime timestamp;
  final CommandType type;
  final String? host;
  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;

  CommandLog({
    this.id,
    required this.timestamp,
    required this.type,
    this.host,
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'host': host,
      'command': command,
      'stdout': stdout,
      'stderr': stderr,
      'exit_code': exitCode,
    };
  }

  factory CommandLog.fromMap(Map<String, dynamic> map) {
    return CommandLog(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      type: CommandType.values.firstWhere((e) => e.name == map['type']),
      host: map['host'] as String?,
      command: map['command'] as String,
      stdout: map['stdout'] as String,
      stderr: map['stderr'] as String,
      exitCode: map['exit_code'] as int,
    );
  }

  String get formattedTimestamp {
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    } catch (e) {
      return timestamp.toIso8601String();
    }
  }
}