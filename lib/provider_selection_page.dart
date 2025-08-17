// lib/provider_selection_page.dart
import 'package:flutter/material.dart';
import 'models/dns_provider.dart';

const Color kBackgroundColor = Color(0xFF1A1A2E);
const Color kAccentColor = Colors.green;

class ProviderSelectionPage extends StatefulWidget {
  const ProviderSelectionPage({super.key});

  @override
  _ProviderSelectionPageState createState() => _ProviderSelectionPageState();
}

class _ProviderSelectionPageState extends State<ProviderSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  late List<DNSProvider> _filteredProviders;
  DNSProvider? _previewSelected; // preview (highlighted) provider

  @override
  void initState() {
    super.initState();
    _filteredProviders = List.from(dnsProviders);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredProviders = List.from(dnsProviders);
      } else {
        _filteredProviders =
            dnsProviders.where((p) {
              return p.name.toLowerCase().contains(q) ||
                  p.type.toLowerCase().contains(q) ||
                  p.features.any((f) => f.toLowerCase().contains(q));
            }).toList();
      }
    });
  }

  void _showDetails(DNSProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (provider.description.isNotEmpty)
                  Text(
                    provider.description,
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(provider.type),
                      backgroundColor: Colors.white10,
                    ),
                    ...provider.features.map(
                      (f) =>
                          Chip(label: Text(f), backgroundColor: Colors.white10),
                    ),
                    if (provider.doh != null)
                      Chip(
                        label: const Text('DoH'),
                        backgroundColor: Colors.white10,
                      ),
                    if (provider.ipv6 != null)
                      Chip(
                        label: const Text('IPv6'),
                        backgroundColor: Colors.white10,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('IPv4 DNS', style: TextStyle(color: kAccentColor)),
                ...provider.dns.map(
                  (d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      d,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                if (provider.ipv6 != null) ...[
                  const SizedBox(height: 8),
                  Text('IPv6 DNS', style: TextStyle(color: kAccentColor)),
                  ...provider.ipv6!.map(
                    (d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        d,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
                if (provider.doh != null) ...[
                  const SizedBox(height: 8),
                  Text('DoH / host', style: TextStyle(color: kAccentColor)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      provider.doh!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _previewSelected = provider);
                        Navigator.pop(context);
                      },
                      child: const Text('Preview'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentColor,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(
                          context,
                          provider,
                        ); // return provider to HomePage
                      },
                      child: const Text(
                        'Select',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTags(DNSProvider provider) {
    final tags = <String>[];
    tags.add(provider.type);
    tags.addAll(provider.features);
    if (provider.doh != null) tags.add('DoH');
    if (provider.ipv6 != null) tags.add('IPv6');

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children:
          tags.map((t) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildProviderTile(DNSProvider provider) {
    final isPreview = provider == _previewSelected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isPreview ? Colors.green.withOpacity(0.08) : kBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPreview ? kAccentColor : Colors.white12,
          width: isPreview ? 1.8 : 1,
        ),
        boxShadow:
            isPreview
                ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
                : [],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: kAccentColor,
          child: Text(
            provider.name[0],
            style: const TextStyle(color: kBackgroundColor),
          ),
        ),
        title: Text(
          provider.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              provider.type,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _buildTags(provider),
          ],
        ),
        trailing: Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.more_horiz, color: kAccentColor),
                onPressed: () => _showDetails(provider),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPreview ? kAccentColor : Colors.white10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                ),
                onPressed: () {
                  // If this is already previewed then select immediately
                  if (isPreview) {
                    Navigator.pop(context, provider);
                  } else {
                    setState(() => _previewSelected = provider);
                  }
                },
                child: Text(
                  isPreview ? 'Select' : 'Preview',
                  style: TextStyle(
                    color: isPreview ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
        onTap: () {
          // quick preview select
          setState(() {
            if (_previewSelected == provider)
              _previewSelected = null;
            else
              _previewSelected = provider;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Select DNS Provider'),
        backgroundColor: kBackgroundColor,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kAccentColor,
                    decoration: InputDecoration(
                      hintText: 'Search providers...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                      prefixIcon: Icon(Icons.search, color: kAccentColor),
                      filled: true,
                      fillColor: const Color(0xFF11121B),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kAccentColor.withOpacity(0.25),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kAccentColor, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                    },
                    icon: const Icon(Icons.clear, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            _filteredProviders.isEmpty
                ? const Center(
                  child: Text(
                    'No providers match your query',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
                : ListView.separated(
                  itemCount: _filteredProviders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final provider = _filteredProviders[index];
                    return _buildProviderTile(provider);
                  },
                ),
      ),
      floatingActionButton:
          _previewSelected != null
              ? FloatingActionButton.extended(
                backgroundColor: kAccentColor,
                onPressed: () {
                  Navigator.pop(context, _previewSelected);
                },
                icon: const Icon(Icons.check, color: Colors.black),
                label: const Text(
                  'Select provider',
                  style: TextStyle(color: Colors.black),
                ),
              )
              : null,
    );
  }
}
