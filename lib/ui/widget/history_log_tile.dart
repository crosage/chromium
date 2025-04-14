import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import '../../models/command_log.dart';

class HistoryLogTile extends StatelessWidget{
  final CommandLog log;
  const HistoryLogTile({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isSuccess = log.exitCode == 0;
    final Color statusColor = isSuccess ? Colors.green : Colors.red;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          log.type==CommandType.powershell?Icons.terminal: Icons.lan,
          color: theme.colorScheme.primary,
        ),
        title:Text(
          log.command,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${log.formattedTimestamp} - Exit: ${log.exitCode}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Icon(
          isSuccess ? Icons.check_circle : Icons.error,
          color: statusColor,
        ),
        children: <Widget>[
          _buildExpandedContent(context, theme, statusColor),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text("复制详情"),
              onPressed: () => _copyDetailsToClipboard(context),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildExpandedContent(BuildContext context, ThemeData theme, Color statusColor){
    return Padding(
      padding: const EdgeInsets.fromLTRB(56.0, 8.0, 16.0, 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1,),
          const SizedBox(height: 12,),
          _buildDetailRow("ID:", log.id?.toString() ?? 'N/A'),
          _buildDetailRow("时间:", log.formattedTimestamp),
          if (log.host != null) _buildDetailRow("主机:", log.host!),
          _buildDetailRow("退出码:", log.exitCode.toString(), valueColor: statusColor),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          const SizedBox(width: 8),
          // 使用 Expanded 让值文本占据剩余的水平空间。
          Expanded(
            // 使用 SelectableText 允许用户复制值文本。
            child: SelectableText(value, style: TextStyle(color: valueColor)),),
        ],
      ),
    );
  }
  Widget _buildOutputBlock(String text,{required String isEmptyText, Color? backgroundColor, Color? textColor}) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color:Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text.isEmpty?isEmptyText:text,
          style: TextStyle(
            fontFamily: "monospace",
            fontSize: 12,
            color:textColor??Colors.black
          ),
        ),
      ),
    );
  }
  void _copyDetailsToClipboard(BuildContext context){
    String details='''
      ID: ${log.id ?? 'N/A'}
      类型: ${log.type.name}
      ${log.host != null ? '主机: ${log.host}\n' : ''}退出码: ${log.exitCode}
      命令:
      ${log.command}
      输出:
      ${log.stdout}
      错误:
      ${log.stderr}
    ''';
    Clipboard.setData(ClipboardData(text: details));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('详情已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }
}