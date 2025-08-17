// lib/admin_page.dart
import 'package:dns_changer/provider_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kAccentColor = Color(0xFF00A86B); // define here if not globally defined

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const MethodChannel _platform = MethodChannel('dns_channel');

  bool _loading = false;
  bool _isDeviceOwner = false;
  String _statusMessage = '';
  String? _lastDpmError;
  String? _lastOperationResult;

  @override
  void initState() {
    super.initState();
    _refreshDeviceOwnerStatus();
  }

  Future<void> _refreshDeviceOwnerStatus() async {
    setState(() {
      _loading = true;
      _statusMessage = '';
      _lastDpmError = null;
      _lastOperationResult = null;
    });
    try {
      final bool isOwner =
          await _platform.invokeMethod<bool>('isDeviceOwner') ?? false;
      setState(() {
        _isDeviceOwner = isOwner;
        _statusMessage =
            isOwner ? 'App is Device Owner' : 'App is NOT Device Owner';
      });
    } on PlatformException catch (e) {
      setState(() {
        _isDeviceOwner = false;
        _statusMessage = 'Failed to query device owner: ${e.message}';
        _lastDpmError = e.details?.toString() ?? e.message;
      });
    } catch (e) {
      setState(() {
        _isDeviceOwner = false;
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestDeviceAdmin() async {
    try {
      await _platform.invokeMethod('requestDeviceAdmin');
      setState(() {
        _lastOperationResult = 'Device admin prompt shown';
      });
      // Re-check status shortly (user must accept)
      await Future.delayed(const Duration(seconds: 1));
      _refreshDeviceOwnerStatus();
    } on PlatformException catch (e) {
      setState(() {
        _lastDpmError = 'requestDeviceAdmin failed: ${e.message}';
      });
    }
  }

  Future<void> _enableAlwaysOnVpn() async {
    if (!_isDeviceOwner) {
      _showNotOwnerDialog();
      return;
    }
    final confirm = await _confirmDialog(
      title: 'Enable Always-On VPN',
      content:
          'Enable Always-On VPN (lockdown) for this app? This requires the app to be device owner and will force traffic through the VPN.',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('enableAlwaysOnVpn');
      setState(() {
        _lastOperationResult =
            res == true
                ? 'Always-On VPN enabled'
                : 'enableAlwaysOnVpn returned: $res';
      });
      await _refreshDeviceOwnerStatus();
    } on PlatformException catch (e) {
      setState(() {
        _lastDpmError = 'enableAlwaysOnVpn failed: ${e.message}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _disableAlwaysOnVpn() async {
    if (!_isDeviceOwner) {
      _showNotOwnerDialog();
      return;
    }
    final confirm = await _confirmDialog(
      title: 'Disable Always-On VPN',
      content: 'Disable Always-On VPN for this app?',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('disableAlwaysOnVpn');
      setState(() {
        _lastOperationResult =
            res == true
                ? 'Always-On VPN disabled'
                : 'disableAlwaysOnVpn returned: $res';
      });
      await _refreshDeviceOwnerStatus();
    } on PlatformException catch (e) {
      setState(() {
        _lastDpmError = 'disableAlwaysOnVpn failed: ${e.message}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _blockUninstall() async {
    if (!_isDeviceOwner) {
      _showNotOwnerDialog();
      return;
    }
    final confirm = await _confirmDialog(
      title: 'Block Uninstall',
      content: 'Block uninstall for this app (device owner only).',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('blockUninstall');
      setState(() {
        _lastOperationResult =
            res == true ? 'Uninstall blocked' : 'blockUninstall returned: $res';
      });
    } on PlatformException catch (e) {
      setState(() {
        _lastDpmError = 'blockUninstall failed: ${e.message}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _unblockUninstall() async {
    if (!_isDeviceOwner) {
      _showNotOwnerDialog();
      return;
    }
    final confirm = await _confirmDialog(
      title: 'Unblock Uninstall',
      content: 'Allow the app to be uninstalled again?',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('unblockUninstall');
      setState(() {
        _lastOperationResult =
            res == true
                ? 'Uninstall unblocked'
                : 'unblockUninstall returned: $res';
      });
    } on PlatformException catch (e) {
      setState(() {
        _lastDpmError = 'unblockUninstall failed: ${e.message}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Proceed'),
              ),
            ],
          ),
    );
  }

  void _showNotOwnerDialog() {
    showDialog<void>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Not device owner'),
            content: const Text(
              'This action requires the app to be the device owner (managed device). Follow provisioning steps to set this app as device owner.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _copyToClipboard(String text, {String? toast}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(toast ?? 'Copied to clipboard')));
    }
  }

  Widget _provisioningCard() {
    // Note: adb method only works on fresh reset devices (see Android docs)
    final adbCmd =
        'adb shell dpm set-device-owner "com.example.dns_changer/.ShieldDeviceAdminReceiver"';
    final notes =
        'ADB provisioning requires a device in factory-reset state (or using Android Management/EMM for managed provisioning).';
    return Card(
      color: const Color(0xFF121227),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provisioning & Device Owner',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              notes,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    adbCmd,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy ADB command',
                  onPressed:
                      () =>
                          _copyToClipboard(adbCmd, toast: 'ADB command copied'),
                  icon: const Icon(Icons.copy, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: _requestDeviceAdmin,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Request Device Admin'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                  ),
                  onPressed: _isDeviceOwner ? _enableAlwaysOnVpn : null,
                  icon: const Icon(Icons.vpn_lock),
                  label: const Text('Enable Always-On'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Card(
      color: const Color(0xFF121227),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Owner Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _isDeviceOwner ? Colors.green : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _refreshDeviceOwnerStatus,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (_lastOperationResult != null)
              Text(
                'Last result: $_lastOperationResult',
                style: const TextStyle(color: Colors.white70),
              ),
            if (_lastDpmError != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Last DPM error (details)',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SelectableText(
                _lastDpmError ?? '',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kAccentColor),
                onPressed: _isDeviceOwner ? _enableAlwaysOnVpn : null,
                child: const Text('Enable Always-On VPN'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: _isDeviceOwner ? _disableAlwaysOnVpn : null,
                child: const Text('Disable Always-On'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _isDeviceOwner ? _blockUninstall : null,
                child: const Text('Block Uninstall'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                onPressed: _isDeviceOwner ? _unblockUninstall : null,
                child: const Text('Unblock Uninstall'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin / Device Owner')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _statusCard(),
            const SizedBox(height: 12),
            _provisioningCard(),
            const SizedBox(height: 12),
            _actionButtons(),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text(
                      'Provisioning note: setting the app as Device Owner requires special provisioning (ADB or EMM). Read docs before proceeding.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (!_isDeviceOwner)
                      ElevatedButton.icon(
                        onPressed: _requestDeviceAdmin,
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('Show device-admin prompt'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
