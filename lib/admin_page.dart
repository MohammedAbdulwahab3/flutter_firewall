// lib/admin_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshDeviceOwnerStatus();
  }

  Future<void> _refreshDeviceOwnerStatus() async {
    setState(() {
      _loading = true;
      _statusMessage = '';
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
        _statusMessage = 'Failed to query device owner: ${e.message}';
        _isDeviceOwner = false;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestDeviceAdmin() async {
    // This shows the legacy "add device admin" UI. The user must confirm.
    try {
      await _platform.invokeMethod('requestDeviceAdmin');
      // After user action, re-check status later
      setState(
        () =>
            _statusMessage =
                'Device admin prompt shown. Complete the flow on the device.',
      );
      await Future.delayed(const Duration(seconds: 1));
      _refreshDeviceOwnerStatus();
    } on PlatformException catch (e) {
      setState(
        () => _statusMessage = 'requestDeviceAdmin failed: ${e.message}',
      );
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
          'Enable Always-On VPN (lockdown) for this app? This requires the app to be device owner. This will force device traffic through the VPN.',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('enableAlwaysOnVpn');
      setState(
        () =>
            _statusMessage =
                res == true
                    ? 'Always-On VPN enabled'
                    : 'enableAlwaysOnVpn returned: $res',
      );
    } on PlatformException catch (e) {
      setState(() => _statusMessage = 'enableAlwaysOnVpn failed: ${e.message}');
    } finally {
      setState(() => _loading = false);
      await _refreshDeviceOwnerStatus();
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
      setState(
        () =>
            _statusMessage =
                res == true
                    ? 'Always-On VPN disabled'
                    : 'disableAlwaysOnVpn returned: $res',
      );
    } on PlatformException catch (e) {
      setState(
        () => _statusMessage = 'disableAlwaysOnVpn failed: ${e.message}',
      );
    } finally {
      setState(() => _loading = false);
      await _refreshDeviceOwnerStatus();
    }
  }

  Future<void> _blockUninstall() async {
    if (!_isDeviceOwner) {
      _showNotOwnerDialog();
      return;
    }
    final confirm = await _confirmDialog(
      title: 'Block Uninstall',
      content:
          'Block uninstall for this app (device-owner only). Admins can still remove it via Device Policy Manager or factory reset.',
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await _platform.invokeMethod('blockUninstall');
      setState(
        () =>
            _statusMessage =
                res == true
                    ? 'Uninstall blocked'
                    : 'blockUninstall returned: $res',
      );
    } on PlatformException catch (e) {
      setState(() => _statusMessage = 'blockUninstall failed: ${e.message}');
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
      setState(
        () =>
            _statusMessage =
                res == true
                    ? 'Uninstall unblocked'
                    : 'unblockUninstall returned: $res',
      );
    } on PlatformException catch (e) {
      setState(() => _statusMessage = 'unblockUninstall failed: ${e.message}');
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
              'This action requires the app to be the device owner (managed device). Follow the provisioning steps to set this app as device owner.',
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

  Widget _buildButton(String label, VoidCallback onPressed, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color),
        onPressed: _loading ? null : onPressed,
        child: Text(label),
      ),
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
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Device owner: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  _isDeviceOwner ? 'YES' : 'NO',
                  style: TextStyle(
                    color: _isDeviceOwner ? Colors.green : Colors.red,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _refreshDeviceOwnerStatus,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusMessage),
            const SizedBox(height: 16),
            _buildButton(
              'Request Device Admin (legacy prompt)',
              _requestDeviceAdmin,
            ),
            const Divider(),
            _buildButton(
              'Enable Always-On VPN (device owner only)',
              _enableAlwaysOnVpn,
              color: Colors.green,
            ),
            _buildButton(
              'Disable Always-On VPN',
              _disableAlwaysOnVpn,
              color: Colors.orange,
            ),
            const Divider(),
            _buildButton(
              'Block Uninstall (device owner only)',
              _blockUninstall,
              color: Colors.red,
            ),
            _buildButton(
              'Unblock Uninstall',
              _unblockUninstall,
              color: Colors.grey,
            ),
            const Spacer(),
            const Text(
              'Provisioning note: setting the app as Device Owner requires special provisioning (ADB or EMM). Read docs before proceeding.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
