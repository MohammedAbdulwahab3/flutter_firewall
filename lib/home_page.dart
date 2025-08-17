// lib/home_page.dart
import 'dart:async';
import 'package:dns_changer/per_app_tabs.dart';
import 'package:dns_changer/ui/config_next_dns.dart';
import 'package:dns_changer/ui/denylist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/dns_provider.dart';
import 'provider_selection_page.dart';
import 'package:dns_changer/admin_page.dart';
import 'services/nextdns_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const MethodChannel _platform = MethodChannel('dns_channel');

  // Query method constants kept from your original app
  static const int QUERY_METHOD_UDP = 0;
  static const int QUERY_METHOD_TCP = 1;
  static const int QUERY_METHOD_HTTPS = 2; // DoH (IETF binary)
  static const int QUERY_METHOD_TLS = 3; // DoT (TLS)
  static const int QUERY_METHOD_HTTPS_JSON = 4; // DoH JSON

  DNSProvider? _selectedProvider;
  bool _isRunning = false;

  // runtime NextDNS creds (kept in-memory only — not persisted)
  String? _nextDnsProfileId; // optional: set via UI
  String? _nextDnsApiKey; // do not hardcode secrets in source

  // uptime
  DateTime? _connectedAt;
  Timer? _uptimeTimer;
  String _uptimeText = '';

  // small status message shown below UI
  String _statusMessage = '';

  // animation controllers for power button
  late final AnimationController _glowController;
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      lowerBound: 0.0,
      upperBound: 0.06,
    );
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _glowController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  // -----------------------
  // Uptime helpers
  // -----------------------
  void _startUptimeTimer() {
    _uptimeTimer?.cancel();
    _connectedAt = DateTime.now();
    _updateUptimeText();
    _uptimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateUptimeText(),
    );
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _connectedAt = null;
    setState(() {
      _uptimeText = '';
    });
  }

  void _updateUptimeText() {
    if (_connectedAt == null) {
      setState(() => _uptimeText = '');
      return;
    }
    final d = DateTime.now().difference(_connectedAt!);
    two(int v) => v.toString().padLeft(2, '0');
    final h = two(d.inHours);
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    setState(() => _uptimeText = '$h:$m:$s');
  }

  // -----------------------
  // Platform interaction (keeps your original semantics)
  // -----------------------
  Future<void> _startVpnForProvider({
    required DNSProvider provider,
    required int queryMethod,
    required int port1,
    int? port2,
    bool? useLocalBlocklistOverride,
  }) async {
    String upstreamArg = provider.dns.isNotEmpty ? provider.dns[0] : '';

    // NextDNS profile has special host
    if (provider.name.toLowerCase().contains('nextdns') &&
        _nextDnsProfileId != null &&
        _nextDnsProfileId!.isNotEmpty) {
      upstreamArg = 'dns.nextdns.io/${_nextDnsProfileId!.trim()}';
      queryMethod = QUERY_METHOD_HTTPS;
    } else if (provider.doh != null && provider.doh!.isNotEmpty) {
      // If doh is provided, use it as upstreamArg and set HTTPS. Also extract explicit port if present
      final doh = provider.doh!.trim();
      upstreamArg = doh;
      queryMethod = QUERY_METHOD_HTTPS;

      try {
        final u = Uri.parse(doh.startsWith('http') ? doh : 'https://$doh');
        if (u.hasPort) {
          port1 = u.port;
        } else {
          // if doh uses default https port and this is a local provider, still keep 8053 special case handled below
        }
      } catch (_) {}
    } else {
      if ((queryMethod == QUERY_METHOD_HTTPS ||
              queryMethod == QUERY_METHOD_HTTPS_JSON) &&
          !upstreamArg.contains('/')) {
        upstreamArg = '$upstreamArg/dns-query';
      }
    }

    // Determine whether we should use local blocklist. For 'Local' type, default to true.
    final useLocalBlocklist =
        useLocalBlocklistOverride ??
        (provider.type.toLowerCase() == 'custom' ||
            provider.name.toLowerCase().contains('custom') ||
            provider.type.toLowerCase().contains('local') ||
            provider.name.toLowerCase().contains('local'));

    // Build args. Ensure that provider.dns[1] passed if exists.
    final args = <String, Object>{
      'dns1': upstreamArg,
      if (provider.dns.length > 1) 'dns2': provider.dns[1],
      'queryMethod': queryMethod,
      'port1': port1,
      'port2': port2 ?? port1,
      'useLocalBlocklist': useLocalBlocklist,
    };

    setState(() => _statusMessage = 'Starting VPN...');
    try {
      await _platform.invokeMethod('startVpn', args);
      setState(() {
        _isRunning = true;
        _statusMessage = 'VPN started';
      });
      _startUptimeTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('VPN started · useLocalBlocklist=$useLocalBlocklist'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunning = false;
        _statusMessage = 'Failed to start VPN';
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start VPN: $e')));
    }
  }

  Map<String, int> _mapProviderToMethodAndPort(DNSProvider p) {
    final featuresLc = p.features.map((f) => f.toLowerCase()).toList();
    final typeLc = p.type.toLowerCase();
    final nameLc = p.name.toLowerCase();

    // Local servers use 8053 in your setup
    if (typeLc.contains('local') || nameLc.contains('local')) {
      // If the provider has a doh with explicit port, we may override port when starting.
      return {'method': QUERY_METHOD_UDP, 'port': 8053};
    }

    if (featuresLc.any((f) => f.contains('encrypted'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    if (featuresLc.any((f) => f.contains('doh') || f.contains('https')) ||
        typeLc.contains('https') ||
        nameLc.contains('doh') ||
        nameLc.contains('https')) {
      return {'method': QUERY_METHOD_HTTPS, 'port': 443};
    }

    if (featuresLc.any((f) => f.contains('dot') || f.contains('tls'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    if (nameLc.contains('mullvad')) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    return {'method': QUERY_METHOD_UDP, 'port': 53};
  }

  Future<void> _toggleVpn() async {
    if (_isRunning) {
      try {
        await _platform.invokeMethod('stopVpn');
      } catch (e) {
        // ignore
      }
      setState(() {
        _isRunning = false;
        _statusMessage = 'VPN stopped';
      });
      _stopUptimeTimer();
      return;
    }

    if (_selectedProvider == null) {
      _showSnackbar('Please select a DNS provider first');
      return;
    }

    final mapping = _mapProviderToMethodAndPort(_selectedProvider!);
    final method = mapping['method']!;
    final port = mapping['port']!;

    await _startVpnForProvider(
      provider: _selectedProvider!,
      queryMethod: method,
      port1: port,
      port2: port,
    );
  }

  Future<void> _goToSelection() async {
    final result = await Navigator.push<DNSProvider>(
      context,
      MaterialPageRoute(builder: (_) => const ProviderSelectionPage()),
    );
    if (result != null) {
      // if already running, restart with new provider
      final wasRunning = _isRunning;
      if (wasRunning) {
        try {
          await _platform.invokeMethod('stopVpn');
        } catch (_) {}
      }
      setState(() => _selectedProvider = result);

      if (wasRunning) {
        final mapping = _mapProviderToMethodAndPort(_selectedProvider!);
        await _startVpnForProvider(
          provider: _selectedProvider!,
          queryMethod: mapping['method']!,
          port1: mapping['port']!,
          port2: mapping['port']!,
        );
      }
    }
  }

  Future<void> _showNextDnsConfigDialog() async {
    final pidCtrl = TextEditingController(text: _nextDnsProfileId ?? '');
    final keyCtrl = TextEditingController(text: _nextDnsApiKey ?? '');
    final res = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('NextDNS Configuration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pidCtrl,
                  decoration: const InputDecoration(labelText: 'Profile ID'),
                ),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Find profile id and API key at https://my.nextdns.io (Endpoints / Account)',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (res == true) {
      setState(() {
        _nextDnsProfileId = pidCtrl.text.trim();
        _nextDnsApiKey = keyCtrl.text.trim();
        _statusMessage = 'NextDNS config set (in-memory)';
      });
      _showSnackbar('NextDNS credentials set (in-memory)');
    }
  }

  void _showSnackbar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildProviderCard() {
    final p = _selectedProvider;
    return Card(
      color: const Color(0xFF121227),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _isRunning ? Colors.green : Colors.grey.shade800,
              child: Text(
                p?.name.substring(0, 1).toUpperCase() ?? '?',
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  p == null
                      ? GestureDetector(
                        onTap: _goToSelection,
                        child: const Text(
                          'No provider selected — tap to choose',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _providerSubtitle(p),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (p.features.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    p.features.first,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _goToSelection,
                                child: const Text(
                                  'Change',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isRunning ? Icons.check_circle : Icons.cancel,
                  color: _isRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 6),
                Text(
                  _isRunning ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: _isRunning ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _providerSubtitle(DNSProvider p) {
    final mapping = _mapProviderToMethodAndPort(p);
    final method = mapping['method']!;
    final port = mapping['port']!;
    final upstream =
        (p.name.toLowerCase().contains('nextdns') && _nextDnsProfileId != null)
            ? 'profile:$_nextDnsProfileId'
            : (p.doh ?? (p.dns.isNotEmpty ? p.dns[0] : ''));
    final methodText =
        method == QUERY_METHOD_UDP
            ? 'UDP:$port'
            : method == QUERY_METHOD_TCP
            ? 'TCP:$port'
            : method == QUERY_METHOD_TLS
            ? 'DoT:$port'
            : 'DoH:$port';
    return '$methodText · ${upstream.toString()}';
  }

  Widget _buildPowerButton() {
    final scale = 1.0 - _pressController.value;
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: () async {
        await _toggleVpn();
      },
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.94).animate(
          CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
        ),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glow =
                (_glowController.value * 0.7) + (_isRunning ? 0.3 : 0.0);
            return Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 4),
                boxShadow:
                    _isRunning
                        ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.18 * glow),
                            blurRadius: 30 * glow,
                            spreadRadius: 1 * glow,
                          ),
                          BoxShadow(
                            color: Colors.green.withOpacity(0.08 * glow),
                            blurRadius: 6 * glow,
                            spreadRadius: 0.5 * glow,
                          ),
                        ]
                        : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 0.5,
                          ),
                        ],
              ),
              child: Center(
                child: Icon(
                  _isRunning ? Icons.power_off : Icons.power_settings_new,
                  size: 68,
                  color: Colors.green,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // -----------------------
  // Page build
  // -----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Net – IPv4 & IPv6'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showNextDnsConfigDialog,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          children: [
            // provider card
            _buildProviderCard(),
            const SizedBox(height: 18),

            // central power button
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPowerButton(),
                  const SizedBox(height: 12),
                  Text(
                    _isRunning ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 18, color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                  if (_isRunning && _uptimeText.isNotEmpty)
                    Text(
                      'Uptime: $_uptimeText',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  if (!_isRunning && _statusMessage.isNotEmpty)
                    Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white60),
                    ),
                ],
              ),
            ),

            // bottom status row
            Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Row(
                children: [
                  Icon(
                    _isRunning ? Icons.wifi : Icons.signal_cellular_off,
                    color: _isRunning ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRunning
                          ? 'Connected · ${_selectedProvider?.name ?? ""}'
                          : (_statusMessage.isNotEmpty
                              ? _statusMessage
                              : 'Disconnected'),
                      style: TextStyle(
                        color: _isRunning ? Colors.green : Colors.white70,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _goToSelection,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Change'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF16213E)),
            child: Text(
              'SecureNet',
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Per-app filter'),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerAppTabsPage()),
                ),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Admin'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('Denylist'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DenylistPageStandalone()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('Config nextDNS'),
            onTap: () {
              if (_nextDnsProfileId == null || _nextDnsApiKey == null) {
                _showSnackbar('Configure NextDNS first');
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => ConfigNextDns(
                        profileId: _nextDnsProfileId!,
                        apiKey: _nextDnsApiKey!,
                      ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
