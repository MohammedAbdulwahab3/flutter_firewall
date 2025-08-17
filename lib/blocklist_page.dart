import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlocklistPage1 extends StatefulWidget {
  const BlocklistPage1({super.key});
  @override
  State<BlocklistPage1> createState() => _BlocklistPageState();
}

class _BlocklistPageState extends State<BlocklistPage1> {
  static const MethodChannel _ch = MethodChannel('dns_channel');
  final TextEditingController _ctrl = TextEditingController();
  final List<String> _domains = [];

  Future<void> _push() async {
    try {
      await _ch.invokeMethod('updateBlocklist', {'domains': _domains});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pushed ${_domains.length} domains')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _add() {
    final d = _ctrl.text.trim().toLowerCase();
    if (d.isEmpty) return;
    setState(() {
      if (!_domains.contains(d)) _domains.add(d);
      _ctrl.clear();
    });
  }

  Future<void> _importDialog() async {
    final TextEditingController importCtrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Import domains (CSV / newline)'),
            content: TextField(
              controller: importCtrl,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText:
                    'Paste domains (one per line or comma separated)\nexample.com, ads.example',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import'),
              ),
            ],
          ),
    );

    if (res != true) return;
    final text = importCtrl.text;
    if (text.trim().isEmpty) return;
    final candidates = <String>[];
    // split on newline or comma
    for (final part in text.split(RegExp(r'[\r\n,]+'))) {
      final d = part.trim().toLowerCase();
      if (d.isEmpty) continue;
      // normalize typical variants
      final normalized = d
          .replaceAll(RegExp(r'^\*\.'), '')
          .replaceAll(RegExp(r'/$'), '')
          .replaceAll(RegExp(r'https?://'), '');
      candidates.add(normalized);
    }
    setState(() {
      for (final c in candidates) if (!_domains.contains(c)) _domains.add(c);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${candidates.length} domains')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Domain blocklist'),
        actions: [
          TextButton(
            onPressed: _push,
            child: const Text('Push', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _importDialog,
            child: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'example.com or ads.example',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _add, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  _domains.isEmpty
                      ? const Center(child: Text('No domains'))
                      : ListView.builder(
                        itemCount: _domains.length,
                        itemBuilder: (ctx, i) {
                          final d = _domains[i];
                          return ListTile(
                            title: Text(d),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed:
                                  () => setState(() => _domains.removeAt(i)),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
