import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OutputDisplay extends StatelessWidget {
  final String output;

  const OutputDisplay({super.key, required this.output});

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Stack(
          children: [
            SelectionArea(
              child: SingleChildScrollView(
                child: Text(
                  output.isEmpty ? '在此处显示输出...' : output,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),

            if (output.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制输出',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: output));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('输出已复制到剪贴板'), duration: Duration(seconds: 1)),
                    );
                  },
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                ),
              ),
          ],
        )
    );
  }
}