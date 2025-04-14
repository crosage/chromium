import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/command_log.dart';
import '../../services/database.dart';
import '../../services/powershell_service.dart';
import '../../services/ssh_service.dart';
import '../widget/history_log_tile.dart';
import '../widget/output_display.dart';
import 'home_screen.dart';

class ExecuteIntent extends Intent{
  const ExecuteIntent();
}

class ExecuteAction extends Action<ExecuteIntent> {
  ExecuteAction(this.onExecute);
  final VoidCallback onExecute;

  @override
  Object? invoke(ExecuteIntent intent) {
    onExecute();
    return null;
  }
}

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState()=> _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>{
  late final DatabaseService _dbService;
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _hostController = TextEditingController(text: kDebugMode ? '192.168.1.XXX' : '');
  final TextEditingController _portController = TextEditingController(text: '22');
  final TextEditingController _userController = TextEditingController(text: kDebugMode ? 'root' : '');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _commandFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  CommandType _selectedType = Platform.isWindows ? CommandType.powershell : CommandType.ssh;
  String _lastOutput="上次执行的输出...";
  bool _isLoadingCommand=false;
  bool _isLoadingHistory=false;

  List<String> _commandHistory=[];
  int _historyIndex=0;

  List<CommandLog> _logs=[];
  DateTimeRange? _selectedDateRange;
  String _activeSearchKeyword = '';

  @override
  void initState() {
    super.initState();
    _dbService = Provider.of<DatabaseService>(context, listen: false);
    _loadCommandHistory();
    _fetchLogs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_commandFocusNode);
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    _commandFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCommandHistory() async {
    _commandHistory = await _dbService.getCommandHistory();
    _historyIndex = _commandHistory.length;
    if (kDebugMode) print("加载了 ${_commandHistory.length} 条历史命令");
  }

  Future <void> _fetchLogs() async{
    if (!mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      List<CommandLog> fetchedLogs;
      final keyword = _activeSearchKeyword.trim();
      final range = _selectedDateRange;
      if (range != null && keyword.isNotEmpty) {
        final startDateStr = DateFormat('yyyy-MM-dd').format(range.start);
        final endDateStr = DateFormat('yyyy-MM-dd').format(range.end);
        fetchedLogs = await _dbService.searchLogsByDateAndKeyword(startDateStr, endDateStr, keyword);
      } else if (range != null && keyword.isEmpty) {
        final startDateStr = DateFormat('yyyy-MM-dd').format(range.start);
        final endDateStr = DateFormat('yyyy-MM-dd').format(range.end);
        fetchedLogs = await _dbService.getLogsByDateRange(startDateStr, endDateStr);
      } else if (range == null && keyword.isNotEmpty) {
        fetchedLogs = await _dbService.searchLogs(keyword);
      } else {
        fetchedLogs = await _dbService.getAllLogs(limit: 200);
      }
      if (mounted) setState(() => _logs = fetchedLogs);
    } catch (e) {
      if (kDebugMode) print("加载历史记录时出错: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载历史记录失败: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
      _fetchLogs();
    }
  }

  void _clearFilters(){
    _searchController.clear();
    setState(() {
      _selectedDateRange = null;
      _activeSearchKeyword = '';
    });
    _fetchLogs();
  }

  void _onSearchSubmitted(String keyword) {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword == _activeSearchKeyword) return;
    setState(() => _activeSearchKeyword = trimmedKeyword);
    _fetchLogs();
  }

  void _navigateHistory(bool goUp) {
    //处理键盘上下
    final int historyCount = _commandHistory.length;
    if (historyCount == 0) return;
    int newIndex = _historyIndex;
    if (goUp) { newIndex = (_historyIndex - 1).clamp(0, historyCount); }
    else { newIndex = (_historyIndex + 1).clamp(0, historyCount); }
    if (newIndex == _historyIndex) return;
    _historyIndex = newIndex;
    if (_historyIndex == historyCount) { _commandController.clear(); }
    else {
      final historyCommand = _commandHistory[_historyIndex];
      _commandController.text = historyCommand;
      _commandController.selection = TextSelection.fromPosition(
        TextPosition(offset: _commandController.text.length),
      );
    }
  }

  Future<void> _executeCommand()async{
    if(_isLoadingCommand) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoadingCommand=true;
      _lastOutput= '正在执行 ${_selectedType.name} 命令...';
    });

    CommandLog? resultLog;
    final command = _commandController.text;
    bool executionAttempted = false;
    try {
      if (_selectedType == CommandType.powershell) {
        if (command.trim().isEmpty) { _lastOutput = '错误: PowerShell 命令不能为空。'; }
        else {
          executionAttempted = true;
          resultLog = await PowerShellService.execute(command);
        }
      } else { // SSH
        final host = _hostController.text.trim();
        final portString = _portController.text;
        final user = _userController.text.trim();
        final password = _passwordController.text;
        final port = int.tryParse(portString);

        if (host.isEmpty || user.isEmpty || command.trim().isEmpty || port == null) { _lastOutput = '错误: SSH 主机、端口、用户名和命令不能为空。'; }
        else if (password.isEmpty) { _lastOutput = '错误: SSH 密码不能为空。'; }
        else {
          executionAttempted = true;
          resultLog = await SSHService.execute( host: host, port: port, username: user, password: password, command: command.trim() );
        }
      }
      if (resultLog != null) {
        _updateLastOutput(resultLog); // 更新上次输出区域
        if (resultLog.exitCode > -90) {
          await _dbService.addLog(resultLog);
          print("日志已记录到数据库");
          // 执行成功后，刷新历史列表 和 键盘导航历史
          await Future.wait([_fetchLogs(), _loadCommandHistory()]);
          _historyIndex = _commandHistory.length; // 重置索引
          _commandController.clear(); // 清空命令输入框
        }
      } else if (executionAttempted) {
        _lastOutput = '错误: 执行服务未返回有效结果。';
        if (kDebugMode) print("警告: 执行服务返回了 null");
      }
      // 如果没有尝试执行 (输入验证失败)，_lastOutput 已被设置错误信息

    } catch (e) {
      _lastOutput = '执行命令时发生意外错误: $e';
      if (kDebugMode) print("执行命令时发生意外错误: $e");
    } finally {
      if (mounted) {
        setState(() { _isLoadingCommand = false; });
      }
    }
  }
  void _updateLastOutput(CommandLog log) {
    _lastOutput = '''
      [${log.formattedTimestamp}] ${log.type.name}${log.type == CommandType.ssh ? ' (${log.sshTargetString})' : ''}
      命令: ${log.command}
      退出码: ${log.exitCode}
      --- stdout ---
      ${log.stdout.trim().isEmpty ? '(无)' : log.stdout.trim()}
      --- stderr ---
      ${log.stderr.trim().isEmpty ? '(无)' : log.stderr.trim()}
    ''';
  }

  String _buildFilterText() {
    List<String> filters = [];
    if (_selectedDateRange != null) {
      final start = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      final end = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('$start 到 $end');
    } else {
      filters.add('所有时间');
    }
    if (_activeSearchKeyword.isNotEmpty) {
      filters.add('关键字: "$_activeSearchKeyword"');
    }
    if (!_isLoadingHistory) {
      filters.add('共 ${_logs.length} 条');
    }
    return '当前显示: ${filters.join(' | ')}';
  }
  void _toggleCommandType() {
    setState(() {
      _selectedType = (_selectedType == CommandType.ssh)
          ? CommandType.powershell
          : CommandType.ssh;
    });
  }
  Widget _buildBottomInputArea() {
    return Material(
      elevation: 4.0,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Actions(
          actions: <Type, Action<Intent>>{
            ExecuteIntent: ExecuteAction(_executeCommand),
          },
          //触发器
          child: Shortcuts(
            shortcuts: <LogicalKeySet, Intent>{
              LogicalKeySet(LogicalKeyboardKey.enter): const ExecuteIntent(),
            },
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_selectedType == CommandType.ssh ? Icons.lan : Icons.terminal),
                  tooltip: _selectedType == CommandType.ssh ? '切换到 PowerShell' : '切换到 SSH',
                  onPressed: Platform.isWindows ? _toggleCommandType : null,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    focusNode: _commandFocusNode,
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      controller: _commandController,
                      decoration: InputDecoration(
                        hintText: '输入 ${_selectedType.name} 命令...',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _executeCommand(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isLoadingCommand
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
                    : IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: '执行命令',
                  onPressed: _isLoadingCommand ? null : _executeCommand,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('powerdealer'), // Use the actual app name if different
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新历史记录',
            onPressed: _isLoadingHistory ? null : _fetchLogs,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0), // Adjust padding, bottom handled by input row
        child: Column( // Main layout: Scrollable content above, fixed input below
          children: [
            Expanded( // Scrollable area
              child: SingleChildScrollView(
                controller: _scrollController, // Assign controller
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Content inside scroll view ---

                    // Conditionally show SSH fields if SSH is selected
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return SizeTransition(sizeFactor: animation, child: child);
                      },
                      child: _selectedType == CommandType.ssh
                          ? _buildSshInputFields() // Keep SSH fields grouped
                          : const SizedBox.shrink(key: ValueKey('no_ssh_fields')),
                    ),
                    if (_selectedType == CommandType.ssh) const SizedBox(height: 16),
                    const Text('历史记录:', style: TextStyle(fontWeight: FontWeight.bold)),
                    _buildHistoryFilterControls(), // Search and date filters
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(_buildFilterText(), style: Theme.of(context).textTheme.bodySmall),
                    ),
                    if (_isLoadingHistory) const LinearProgressIndicator(),

                    // History List View
                    if (_logs.isEmpty && !_isLoadingHistory)
                      const Padding( // Show message if empty and not loading
                        padding: EdgeInsets.symmetric(vertical: 32.0),
                        child: Center(child: Text('没有符合条件的记录。', style: TextStyle(color: Colors.grey))),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true, // Crucial for ListView inside SingleChildScrollView
                        physics: const NeverScrollableScrollPhysics(), // Crucial
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          // Use index for key if log.id might not be unique or stable during filtering
                          return HistoryLogTile(key: ValueKey(log.id ?? index), log: log);
                        },
                        separatorBuilder: (context, index) => Divider(
                            height: 1, thickness: 0.5, color: Colors.grey[300]),
                      ),

                    const SizedBox(height: 20), // Add space at the very bottom of scroll content
                  ],
                ),
              ),
            ),

            // --- Fixed Bottom Input Area ---
            _buildBottomInputArea(),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _navigateHistory(true);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _navigateHistory(false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored; // 其他按键忽略，让系统或其他监听器处理
  }
  // 构建 SSH 输入字段的辅助方法
  Widget _buildSshInputFields() {
    return Column(
      key: const ValueKey('ssh_fields'),
      children: [
        TextField(controller: _hostController, decoration: const InputDecoration(labelText: '主机名或IP')),
        const SizedBox(height: 8),
        Row(children: [ /* ... Port, User, Password TextFields ... */
          SizedBox(width: 80, child: TextField(controller: _portController, decoration: InputDecoration(labelText: '端口'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _userController, decoration: InputDecoration(labelText: '用户名'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _passwordController, decoration: InputDecoration(labelText: '密码'), obscureText: true)),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

  // 构建历史记录筛选控件区域的辅助方法
  Widget _buildHistoryFilterControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded( // 搜索框
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索历史记录...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _activeSearchKeyword.isNotEmpty // 使用 active 关键字判断
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: '清除搜索',
                  onPressed: () {
                    _searchController.clear();
                    _onSearchSubmitted('');
                  },
                ) : null,
              ),
              onChanged: (value) => setState((){}), // 仅用于更新清除按钮状态
              onSubmitted: _onSearchSubmitted,
            ),
          ),
          const SizedBox(width: 8),
          // 日期范围按钮
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: '选择日期范围',
            color: Theme.of(context).colorScheme.primary,
            onPressed: _isLoadingHistory ? null : () => _selectDateRange(context),
          ),
          // 清除筛选按钮 (仅当有筛选条件时显示)
          if (_selectedDateRange != null || _activeSearchKeyword.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: '清除所有筛选',
              onPressed: _isLoadingHistory ? null : _clearFilters,
            ),
        ],
      ),
    );
  }

}