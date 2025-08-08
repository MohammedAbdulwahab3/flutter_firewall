// lib/ui/denylist_page.dart
import 'package:flutter/material.dart';
import '../services/nextdns_service.dart';
import '../services/denylist_local_repo.dart';

class DenylistPage extends StatefulWidget {
  final String profileId;
  final String apiKey;
  const DenylistPage({
    super.key,
    required this.profileId,
    required this.apiKey,
  });

  @override
  State<DenylistPage> createState() => _DenylistPageState();
}

class _DenylistPageState extends State<DenylistPage> {
  List<String> _items = [];
  List<String> _filtered = [];
  bool _loading = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocalThenRemote();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
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

  Future<void> _loadLocalThenRemote() async {
    setState(() => _loading = true);

    // 1) Load local cache first
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
      // ignore local load errors
    }

    // 2) Then try remote; only overwrite local if remote returns a non-empty list
    try {
      final remote = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      final normalized = remote.map((e) => e.toLowerCase()).toList()..sort();

      if (normalized.isNotEmpty) {
        // persist remote into Hive (because it's meaningful)
        await DenylistLocalRepo.instance.saveAll(normalized);
        setState(() {
          _items = normalized;
          _filtered = List.from(_items);
        });
      } else {
        // remote empty -> do not overwrite local (preserve local user's list)
        // optionally show a small message:
        debugPrint('NextDNS returned an empty denylist; keeping local cache.');
      }
    } catch (e) {
      // network error -> keep local cache
      debugPrint('Failed to fetch remote denylist: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addDomainDialog() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add domain to denylist'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: 'example.com'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Add'),
              ),
            ],
          ),
    );
    if (res == null || res.isEmpty) return;
    await _addDomain(res);
  }

  Future<void> _addDomain(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) return;

    setState(() => _loading = true);
    try {
      // Read local Hive list
      final localSet =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toSet();

      if (localSet.contains(normalized)) {
        // already present - just update UI
        final list = localSet.toList()..sort();
        setState(() {
          _items = list;
          _filtered = List.from(_items);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$domain already in denylist')));
        return;
      }

      // Add to local set and push full array to NextDNS (setDenylist will update Hive on success)
      localSet.add(normalized);
      final merged = localSet.toList()..sort();

      await NextDnsService.setDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domains: merged,
      );

      // setDenylist updates Hive; reflect the merged list in UI
      setState(() {
        _items = merged;
        _filtered = List.from(_items);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added $domain')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add $domain: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeDomain(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) return;

    setState(() => _loading = true);
    try {
      // Read local Hive list
      final localSet =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toSet();

      if (!localSet.contains(normalized)) {
        // nothing to remove - update UI from local
        final list = localSet.toList()..sort();
        setState(() {
          _items = list;
          _filtered = List.from(_items);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$domain not found in denylist')),
        );
        return;
      }

      // Remove and push full array to NextDNS (setDenylist will update Hive on success)
      localSet.remove(normalized);
      final merged = localSet.toList()..sort();

      await NextDnsService.setDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domains: merged,
      );

      // Reflect update in UI
      setState(() {
        _items = merged;
        _filtered = List.from(_items);
      });

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

  Future<void> _sync() async {
    setState(() => _loading = true);
    try {
      await NextDnsService.syncLocalToRemote(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      // After sync, fetch remote and persist locally (setDenylist already updated local)
      final updated = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      final normalized = updated.map((e) => e.toLowerCase()).toList()..sort();

      if (normalized.isNotEmpty) {
        await DenylistLocalRepo.instance.saveAll(normalized);
        setState(() {
          _items = normalized;
          _filtered = List.from(_items);
        });
      } else {
        // nothing on remote after sync - keep local (syncLocalToRemote should have pushed local already)
        setState(() {
          _items =
              DenylistLocalRepo.instance
                  .getAll()
                  .map((e) => e.toLowerCase())
                  .toList()
                ..sort();
          _filtered = List.from(_items);
        });
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Synced with NextDNS')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Denylist'),
        actions: [IconButton(onPressed: _sync, icon: const Icon(Icons.sync))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDomainDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search denylist...',
              ),
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
                        final domain = _filtered[i];
                        return Dismissible(
                          key: Key(domain),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (dir) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (c) => AlertDialog(
                                    title: const Text('Remove from denylist?'),
                                    content: Text(
                                      'Remove $domain from denylist?',
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
                          onDismissed: (_) => _removeDomain(domain),
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  domain.isNotEmpty
                                      ? domain[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(domain),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed:
                                    () => showModalBottomSheet(
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
                                                  title: const Text(
                                                    'Remove from denylist',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    _removeDomain(domain);
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.copy,
                                                  ),
                                                  title: const Text(
                                                    'Copy domain',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    // optionally copy to clipboard
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                    ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
