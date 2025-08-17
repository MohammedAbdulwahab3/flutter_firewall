// lib/ui/denylist_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../services/denylist_local_repo.dart';

class BlocklistPreset {
  final String id;
  final String name;
  final String description;
  final String url;
  const BlocklistPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
  });
}

const List<BlocklistPreset> kPresets = [
  BlocklistPreset(
    id: 'steveblack',
    name: 'SteveBlack (hosts)',
    description: 'Aggregated hosts-based blocklist (ads, trackers, malware).',
    url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
  ),
  BlocklistPreset(
    id: 'adguard',
    name: 'AdGuard DNS filter (domains)',
    description: 'AdGuard base filter extracted to domains.',
    url: 'https://filters.adtidy.org/extension/chromium/filters/15.txt',
  ),
  BlocklistPreset(
    id: 'oisd',
    name: 'OISD (domains)',
    description: 'Comprehensive community-maintained blocklist.',
    url: 'https://oisd.nl/example/oisd-blocklist.txt',
  ),
];

class DenylistPageStandalone extends StatefulWidget {
  const DenylistPageStandalone({super.key});

  @override
  State<DenylistPageStandalone> createState() => _DenylistPageStandaloneState();
}

class _DenylistPageStandaloneState extends State<DenylistPageStandalone> {
  static const MethodChannel _platform = MethodChannel('dns_channel');

  final TextEditingController _singleCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  List<String> _items = [];
  List<String> _filtered = [];
  bool _loading = false;
  bool _importing = false;
  BlocklistPreset? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _singleCtrl.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered =
          q.isEmpty
              ? List.from(_items)
              : _items.where((s) => s.contains(q)).toList();
    });
  }

  Future<void> _loadLocal() async {
    setState(() => _loading = true);
    try {
      final local =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toList()
            ..sort();
      setState(() {
        _items = local;
        _filtered = List.from(_items);
      });
    } catch (e) {
      debugPrint('load local failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // parse text (hosts / csv / lines) -> domain tokens
  List<String> _parseTextToDomains(String raw) {
    final Set<String> tokens = {};
    final parts = raw.split(RegExp(r'[\r\n,]+'));
    for (var part in parts) {
      var d = part.trim().toLowerCase();
      if (d.isEmpty) continue;
      if (d.startsWith('#')) continue;
      d = d.replaceAll(RegExp(r'https?://'), '');
      d = d.replaceFirst(
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}\s+'),
        '',
      ); // drop leading IP
      d = d.replaceAll(RegExp(r'^\*\.'), ''); // remove wildcard prefix
      if (d.contains('/')) d = d.split('/').first;
      if (d.contains(':')) d = d.split(':').first;
      d = d.trim().trimRight();
      if (d.isEmpty) continue;
      if (d.contains('.') || d.length > 2) tokens.add(d);
    }
    return tokens.toList();
  }

  Future<void> _pushToPlatform(List<String> merged) async {
    // pushes to Kotlin side; Kotlin will persist prefs and start the service with useLocalBlocklist = true
    try {
      await _platform.invokeMethod('updateBlocklist', {'domains': merged});
      // Good UX: inform user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pushed ${merged.length} domains to system')),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to push blocklist: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to push blocklist: $e')));
      }
    }
  }

  Future<void> _addSingleDomain() async {
    final raw = _singleCtrl.text.trim();
    if (raw.isEmpty) return;
    final parsed = _parseTextToDomains(raw);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No valid domain found')));
      return;
    }
    await _applyAddList(parsed);
    _singleCtrl.clear();
  }

  Future<void> _importFromFile() async {
    setState(() => _importing = true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      String content;
      if (f.path != null) {
        content = await File(f.path!).readAsString();
      } else if (f.bytes != null) {
        content = String.fromCharCodes(f.bytes!);
      } else {
        throw Exception('Could not read file');
      }
      final parsed = _parseTextToDomains(content);
      if (parsed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No domains found in file')),
        );
        return;
      }
      await _previewAndConfirm(parsed, sourceLabel: f.name);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      setState(() => _importing = false);
    }
  }

  Future<void> _fetchAndPreviewPreset(BlocklistPreset preset) async {
    setState(() => _loading = true);
    try {
      final resp = await http
          .get(Uri.parse(preset.url))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300)
        throw Exception('HTTP ${resp.statusCode}');
      final parsed = _parseTextToDomains(resp.body);
      if (parsed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preset returned no domains')),
        );
        return;
      }
      await _previewAndConfirm(parsed, sourceLabel: preset.name);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to fetch preset: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _previewAndConfirm(
    List<String> parsed, {
    required String sourceLabel,
  }) async {
    final localSet =
        DenylistLocalRepo.instance.getAll().map((e) => e.toLowerCase()).toSet();
    final newSet = parsed.map((e) => e.toLowerCase()).toSet();
    final onlyNew = newSet.difference(localSet).toList()..sort();
    final dupCount = newSet.length - onlyNew.length;
    final totalToAdd = onlyNew.length;
    final isLarge = totalToAdd > 5000;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: Text('Add list from $sourceLabel?'),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found ${newSet.length} domains. $dupCount already exist locally.',
                  ),
                  const SizedBox(height: 8),
                  if (isLarge)
                    Text(
                      'Large import ($totalToAdd new entries). Proceed carefully.',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  const SizedBox(height: 8),
                  const Text('Preview (first 50 new):'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      child: ListView(
                        children:
                            onlyNew
                                .take(50)
                                .map(
                                  (d) => Text(
                                    d,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
                ],
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

    if (confirmed != true) return;
    await _applyAddList(onlyNew);
  }

  Future<void> _applyAddList(List<String> list) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to add')));
      return;
    }
    setState(() => _loading = true);
    try {
      final local =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toSet();
      local.addAll(list.map((e) => e.toLowerCase()));
      final merged = local.toList()..sort();
      await DenylistLocalRepo.instance.saveAll(merged);

      // push to native side so VPN will read SharedPreferences
      await _pushToPlatform(merged);

      await _loadLocal();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${list.length} domains (local)')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add list: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeDomain(String domain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Remove from denylist?'),
            content: Text('Remove $domain from denylist?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      final local =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toList();
      local.removeWhere((d) => d == domain);
      await DenylistLocalRepo.instance.saveAll(local);

      // push update to native side
      await _pushToPlatform(local);

      await _loadLocal();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed $domain')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove $domain: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _presetRow(BlocklistPreset p) {
    return ListTile(
      title: Text(p.name),
      subtitle: Text(
        p.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ElevatedButton(
        onPressed: () => _fetchAndPreviewPreset(p),
        child: const Text('Add'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Denylist'),
        actions: [
          IconButton(onPressed: _loadLocal, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _importFromFile,
            icon: const Icon(Icons.file_upload),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSingleDomain,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _singleCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.add_link),
                      hintText: 'Add single domain (example.com)',
                    ),
                    onSubmitted: (_) => _addSingleDomain(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addSingleDomain,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<BlocklistPreset>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Add popular blocklist',
                    ),
                    items:
                        kPresets
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedPreset = v),
                    value: _selectedPreset,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      _selectedPreset == null
                          ? null
                          : () => _fetchAndPreviewPreset(_selectedPreset!),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          if (_loading) const LinearProgressIndicator(),

          Expanded(
            child:
                _filtered.isEmpty
                    ? Center(
                      child: Text(
                        _loading ? 'Loading...' : 'Denylist is empty',
                      ),
                    )
                    : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final d = _filtered[i];
                        return Dismissible(
                          key: Key(d),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (c) => AlertDialog(
                                    title: const Text('Remove?'),
                                    content: Text(
                                      'Remove $d from local denylist?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(c, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                            );
                            return ok == true;
                          },
                          onDismissed: (_) => _removeDomain(d),
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  d.isNotEmpty ? d[0].toUpperCase() : '?',
                                ),
                              ),
                              title: Text(d),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder:
                                        (_) => SafeArea(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.delete,
                                                ),
                                                title: const Text('Remove'),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _removeDomain(d);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(Icons.copy),
                                                title: const Text('Copy'),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  Clipboard.setData(
                                                    ClipboardData(text: d),
                                                  );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Copied'),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
