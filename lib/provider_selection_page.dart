// File: lib/provider_selection_page.dart
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

  @override
  void initState() {
    super.initState();
    _filteredProviders = dnsProviders;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProviders = dnsProviders;
      } else {
        _filteredProviders =
            dnsProviders.where((p) {
              return p.name.toLowerCase().contains(query) ||
                  p.type.toLowerCase().contains(query);
            }).toList();
      }
    });
  }

  void _showDetails(DNSProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
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
                  style: const TextStyle(color: Colors.white),
                ),
              const SizedBox(height: 12),
              Text('Features', style: TextStyle(color: kAccentColor)),
              ...provider.features.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.check, size: 16, color: kAccentColor),
                      const SizedBox(width: 8),
                      Text(f, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
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
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Text('DoH / DoH host', style: TextStyle(color: kAccentColor)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
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
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close the bottom sheet
                    Navigator.pop(
                      context,
                      provider,
                    ); // Return provider to HomePage
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Select',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              cursorColor: kAccentColor,
              decoration: InputDecoration(
                hintText: 'Search providers...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: Icon(Icons.search, color: kAccentColor),
                filled: true,
                fillColor: kBackgroundColor,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kAccentColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kAccentColor, width: 2),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredProviders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final provider = _filteredProviders[index];
          return Card(
            color: kBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: kAccentColor),
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: CircleAvatar(
                backgroundColor: kAccentColor,
                child: Text(
                  provider.name[0],
                  style: TextStyle(color: kBackgroundColor),
                ),
              ),
              title: Text(
                provider.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                provider.type,
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _showDetails(provider),
                    style: TextButton.styleFrom(foregroundColor: kAccentColor),
                    child: const Text('Details'),
                  ),
                  Icon(Icons.expand_more, color: kAccentColor),
                ],
              ),
              backgroundColor: kBackgroundColor,
              collapsedBackgroundColor: kBackgroundColor,
              childrenPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        provider,
                      ); // this sends the selected provider back
                    },
                    icon: Icon(Icons.check_circle),
                    label: Text("Select"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
      floatingActionButton:
          _searchController.text.isNotEmpty
              ? FloatingActionButton(
                backgroundColor: kAccentColor,
                onPressed: () {
                  _searchController.clear();
                },
                tooltip: 'Clear search',
                child: const Icon(Icons.clear, color: kBackgroundColor),
              )
              : null,
    );
  }
}
