import 'package:intl/intl.dart'; // 用于日期格式化

enum CommandType { powershell, ssh }

class CommandLog {
  final int? id;
  final DateTime timestamp;
  final CommandType type;
  final String? host;
  final int? port;
  final String? user;
  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;

  CommandLog({
    this.id,
    required this.timestamp,
    required this.type,
    this.host,
    this.port,
    this.user,
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
      'port': port,
      'user': user,
      'command': command,
      'stdout': stdout,
      'stderr': stderr,
      'exit_code': exitCode,
    };
  }

  factory CommandLog.fromMap(Map<String, dynamic> map) {

    int? readInt(String key) => map[key] is int ? map[key] as int : null;
    String? readString(String key) => map[key] is String ? map[key] as String : null;

    return CommandLog(
      id: readInt('id'),
      timestamp: DateTime.parse(map['timestamp'] as String),
      type: CommandType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => CommandType.powershell,
      ),
      host: readString('host'),
      port: readInt('port'),
      user: readString('user'),
      command: map['command'] as String? ?? '',
      stdout: map['stdout'] as String? ?? '',
      stderr: map['stderr'] as String? ?? '',
      exitCode: map['exit_code'] as int? ?? -99,
    );
  }

  String get formattedTimestamp {
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    } catch (e) {
      return timestamp.toIso8601String();
    }
  }

  String get sshTargetString {
    if (type == CommandType.ssh) {
      String target = user ?? 'unknown_user';
      target += '@';
      target += host ?? 'unknown_host';
      if (port != null && port != 22) {
        target += ':$port';
      }
      return target;
    }
    return '';
  }
}