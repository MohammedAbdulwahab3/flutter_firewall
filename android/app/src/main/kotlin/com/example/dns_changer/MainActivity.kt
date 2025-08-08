package com.example.dns_changer

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "dns_channel"
  private val VPN_REQUEST = 1001
  private var pendingDns1 = ""
  private var pendingDns2 = ""
  private var pendingQueryMethod: Int = 0
  private var pendingPort1: Int = 53
  private var pendingPort2: Int = 53

  override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "startVpn" -> {
          pendingDns1 = call.argument<String>("dns1") ?: ""
          pendingDns2 = call.argument<String>("dns2") ?: pendingDns1

          pendingQueryMethod = when (val qm = call.argument<Any>("queryMethod")) {
            is Int -> qm
            is Long -> qm.toInt()
            else -> 0
          }

          pendingPort1 = when (val p = call.argument<Any>("port1")) {
            is Int -> p
            is Long -> p.toInt()
            else -> 53
          }

          pendingPort2 = when (val p = call.argument<Any>("port2")) {
            is Int -> p
            is Long -> p.toInt()
            else -> 53
          }

          prepareVpn()
          result.success(null)
        }
        "stopVpn" -> {
          Intent(this, DnsVpnService::class.java).apply {
            action = DnsVpnService.ACTION_STOP
          }.also { intent ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
          }
          result.success(null)
        }

        // Admin related methods
        "isDeviceOwner" -> {
          val dpm = getSystemService(DevicePolicyManager::class.java)
          result.success(dpm.isDeviceOwnerApp(packageName))
        }

        "requestDeviceAdmin" -> {
          // Launch the legacy admin activation screen (not device owner)
          val admin = ComponentName(this, DeviceAdminReceiver::class.java)
          val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Device admin required for enterprise features")
          }
          startActivity(intent)
          result.success(null)
        }

        "enableAlwaysOnVpn" -> {
          try {
            val admin = ComponentName(this, DeviceAdminReceiver::class.java)
            val dpm = getSystemService(DevicePolicyManager::class.java)
            if (dpm.isDeviceOwnerApp(packageName)) {
              // setAlwaysOnVpnPackage(admin, vpnPackage, lockdown, lockdownAllowedPackages)
              dpm.setAlwaysOnVpnPackage(admin, packageName, true, null)
              result.success(true)
            } else result.error("NOT_OWNER", "App is not device owner", null)
          } catch (e: Exception) {
            result.error("ERR", e.message, null)
          }
        }

        "disableAlwaysOnVpn" -> {
          try {
            val admin = ComponentName(this, DeviceAdminReceiver::class.java)
            val dpm = getSystemService(DevicePolicyManager::class.java)
            if (dpm.isDeviceOwnerApp(packageName)) {
              dpm.setAlwaysOnVpnPackage(admin, null, false, null)
              result.success(true)
            } else result.error("NOT_OWNER", "App is not device owner", null)
          } catch (e: Exception) {
            result.error("ERR", e.message, null)
          }
        }

        "blockUninstall" -> {
          try {
            val admin = ComponentName(this, DeviceAdminReceiver::class.java)
            val dpm = getSystemService(DevicePolicyManager::class.java)
            if (dpm.isDeviceOwnerApp(packageName)) {
              dpm.setUninstallBlocked(admin, packageName, true)
              result.success(true)
            } else result.error("NOT_OWNER", "App is not device owner", null)
          } catch (e: Exception) {
            result.error("ERR", e.message, null)
          }
        }

        "unblockUninstall" -> {
          try {
            val admin = ComponentName(this, DeviceAdminReceiver::class.java)
            val dpm = getSystemService(DevicePolicyManager::class.java)
            if (dpm.isDeviceOwnerApp(packageName)) {
              dpm.setUninstallBlocked(admin, packageName, false)
              result.success(true)
            } else result.error("NOT_OWNER", "App is not device owner", null)
          } catch (e: Exception) {
            result.error("ERR", e.message, null)
          }
        }

        else -> result.notImplemented()
      }
    }
  }

  private fun prepareVpn() {
    val vpnIntent: Intent? = VpnService.prepare(this)
    if (vpnIntent != null) {
      startActivityForResult(vpnIntent, VPN_REQUEST)
    } else {
      onActivityResult(VPN_REQUEST, Activity.RESULT_OK, null)
    }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == VPN_REQUEST && resultCode == Activity.RESULT_OK) {
      val svcIntent = Intent(this, DnsVpnService::class.java).apply {
        action = DnsVpnService.ACTION_START
        putExtra("dns1", pendingDns1)
        putExtra("dns2", pendingDns2)
        putExtra("queryMethod", pendingQueryMethod)
        putExtra("port1", pendingPort1)
        putExtra("port2", pendingPort2)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        startForegroundService(svcIntent)
      } else {
        startService(svcIntent)
      }
    } else {
      Log.e("MainActivity", "VPN permission denied or wrong requestCode")
    }
  }
}
