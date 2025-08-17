package com.example.dns_changer

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
  private val CHANNEL = "dns_channel"
  private val VPN_REQUEST = 1001

  // Pending values used when preparing VPN permission
  private var pendingDns1 = ""
  private var pendingDns2 = ""
  private var pendingQueryMethod: Int = 0
  private var pendingPort1: Int = 53
  private var pendingPort2: Int = 53
  private var pendingAllowedApps: ArrayList<String> = ArrayList()
  private var pendingBlockedApps: ArrayList<String> = ArrayList()
  private var pendingPerAppMode: String? = null // optional: "allow" or "block"

  private var pendingUseLocalBlocklist: Boolean = false

  override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {

        "startVpn" -> {
          // existing logic (same as your previous code)...
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

          val allowed = call.argument<List<String>>("allowedApps")
          pendingAllowedApps = if (allowed != null) ArrayList(allowed) else ArrayList()

          val blocked = call.argument<List<String>>("blockedApps")
          pendingBlockedApps = if (blocked != null) ArrayList(blocked) else ArrayList()

          pendingPerAppMode = call.argument<String>("perAppMode")
          pendingUseLocalBlocklist = call.argument<Boolean>("useLocalBlocklist") ?: false

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

        "listInstalledApps", "listAllApps" -> {
          // your existing implementation...
          try {
            val includeSystem = call.argument<Boolean>("includeSystem") ?: false
            val includeNonLaunchable = call.argument<Boolean>("includeNonLaunchable") ?: false
            val pm = packageManager
            val apps = ArrayList<Map<String, Any>>()
            val installed = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            for (ai in installed) {
              val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
              if (!includeSystem && isSystem) continue
              val pkg = ai.packageName
              val label = pm.getApplicationLabel(ai)?.toString() ?: pkg
              val hasLaunch = pm.getLaunchIntentForPackage(pkg) != null
              if (!includeNonLaunchable && !hasLaunch) continue
              val m = mapOf(
                "label" to label,
                "package" to pkg,
                "isSystem" to isSystem,
                "hasLaunch" to hasLaunch
              )
              apps.add(m)
            }
            result.success(apps)
          } catch (e: Exception) {
            Log.w("MainActivity", "listInstalledApps failed: ${e.message}")
            result.error("ERR", "Failed to list apps: ${e.message}", null)
          }
        }

        "getAppIcon" -> {
          val pkg = call.argument<String>("package")
          if (pkg == null) {
            result.error("ARG", "missing package", null)
            return@setMethodCallHandler
          }
          try {
            val pm = packageManager
            val drawable = pm.getApplicationIcon(pkg)
            val bmp = drawableToBitmap(drawable)
            val baos = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
            val bytes = baos.toByteArray()
            val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            result.success(b64)
          } catch (e: Exception) {
            Log.w("MainActivity", "getAppIcon failed for $pkg: ${e.message}")
            result.success("") // signal "no icon"
          }
        }

        "updatePerAppFilter" -> {
          // existing code (unchanged)...
          try {
            val mode = call.argument<String>("mode") ?: "allow"
            val packages = call.argument<List<String>>("packages") ?: emptyList()
            val operation = call.argument<String>("operation") ?: "add"

            val prefs = getSharedPreferences("shieldguard_prefs", MODE_PRIVATE)
            val allowed = prefs.getStringSet("allowed_apps", emptySet())?.toMutableSet() ?: mutableSetOf()
            val blocked = prefs.getStringSet("blocked_apps", emptySet())?.toMutableSet() ?: mutableSetOf()

            if (mode == "allow") {
              when (operation) {
                "add" -> {
                  allowed.addAll(packages)
                  blocked.removeAll(packages)
                }
                "remove" -> {
                  allowed.removeAll(packages)
                }
                "set" -> {
                  allowed.clear(); allowed.addAll(packages)
                  blocked.removeAll(packages)
                }
                "clear" -> {
                  allowed.clear()
                }
                else -> {
                  allowed.addAll(packages)
                  blocked.removeAll(packages)
                }
              }
            } else {
              when (operation) {
                "add" -> {
                  blocked.addAll(packages)
                  allowed.removeAll(packages)
                }
                "remove" -> {
                  blocked.removeAll(packages)
                }
                "set" -> {
                  blocked.clear(); blocked.addAll(packages)
                  allowed.removeAll(packages)
                }
                "clear" -> {
                  blocked.clear()
                }
                else -> {
                  blocked.addAll(packages)
                  allowed.removeAll(packages)
                }
              }
            }

            prefs.edit().putStringSet("allowed_apps", allowed).putStringSet("blocked_apps", blocked).apply()

            // Restart VPN to apply new rules
            try {
              Intent(this, DnsVpnService::class.java).apply { action = DnsVpnService.ACTION_STOP }.also { stopIntent ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(stopIntent) else startService(stopIntent)
              }
            } catch (_: Exception) {}

            Intent(this, DnsVpnService::class.java).apply {
              action = DnsVpnService.ACTION_START
              if (allowed.isNotEmpty()) putStringArrayListExtra(DnsVpnService.EXTRA_ALLOWED_APPS, ArrayList(allowed))
              if (blocked.isNotEmpty()) putStringArrayListExtra(DnsVpnService.EXTRA_BLOCKED_APPS, ArrayList(blocked))
            }.also { svcIntent ->
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svcIntent) else startService(svcIntent)
            }

            result.success(true)
          } catch (e: Exception) {
            Log.w("MainActivity", "updatePerAppFilter failed: ${e.message}")
            result.error("ERR", "updatePerAppFilter failed: ${e.message}", null)
          }
        }

        // NEW: updateBlocklist - called from Flutter to persist blocklist and tell VPN to use it
        "updateBlocklist" -> {
          try {
            val domains = call.argument<List<String>>("domains") ?: emptyList<String>()
            val prefs = getSharedPreferences("shieldguard_prefs", MODE_PRIVATE)
            // normalize set (lowercase, no trailing dot)
            val normalized = domains.map { it.trim().lowercase().trimEnd('.') }.filter { it.isNotEmpty() }.toSet()
            prefs.edit().putStringSet("blocklist_domains", normalized).apply()
            Log.i("MainActivity", "updateBlocklist saved ${normalized.size} domains")

            // Start / restart VPN service so it picks useLocalBlocklist = true and reads prefs
            Intent(this, DnsVpnService::class.java).apply {
              action = DnsVpnService.ACTION_START
              putExtra("useLocalBlocklist", true)
            }.also { intent ->
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            }

            result.success(true)
          } catch (e: Exception) {
            Log.w("MainActivity", "updateBlocklist failed: ${e.message}")
            result.error("ERR", "updateBlocklist failed: ${e.message}", null)
          }
        }

        // keep existing admin methods unchanged...
        "getPerAppPrefs" -> {
          try {
            val prefs = getSharedPreferences("shieldguard_prefs", MODE_PRIVATE)
            val oldMode = prefs.getString("per_app_mode", null)
            //val raw = prefs.getStringSet("blocklist_domains", emptySet()) ?: emptySet()
            val oldPackages = prefs.getStringSet("per_app_packages", null)
            if (oldMode != null && oldPackages != null) {
              val allowed = prefs.getStringSet("allowed_apps", emptySet())?.toMutableSet() ?: mutableSetOf()
              val blocked = prefs.getStringSet("blocked_apps", emptySet())?.toMutableSet() ?: mutableSetOf()
              if (oldMode == "allow") {
                allowed.addAll(oldPackages)
                blocked.removeAll(oldPackages)
              } else {
                blocked.addAll(oldPackages)
                allowed.removeAll(oldPackages)
              }
              prefs.edit()
                .remove("per_app_mode")
                .remove("per_app_packages")
                .putStringSet("allowed_apps", allowed)
                .putStringSet("blocked_apps", blocked)
                .apply()
            }

            val raw = prefs.getStringSet("blocklist_domains", emptySet()) ?: emptySet()
Log.i("DnsVpnService", "getLocalBlocklist size=${raw.size}")

            val allowedSet = prefs.getStringSet("allowed_apps", emptySet()) ?: emptySet()
            val blockedSet = prefs.getStringSet("blocked_apps", emptySet()) ?: emptySet()
            val map = mapOf("allowed" to allowedSet.toList(), "blocked" to blockedSet.toList())
            result.success(map)
          } catch (e: Exception) {
            result.error("ERR", "getPerAppPrefs failed: ${e.message}", null)
          }
        }

        // Admin helpers (requestDeviceAdmin, enableAlwaysOnVpn, disableAlwaysOnVpn, blockUninstall, unblockUninstall)
        "isDeviceOwner" -> {
          try {
            val dpm = getSystemService(DevicePolicyManager::class.java)
            result.success(dpm.isDeviceOwnerApp(packageName))
          } catch (e: Exception) {
            result.error("ERR", e.message, null)
          }
        }

        "requestDeviceAdmin" -> {
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

  private fun drawableToBitmap(drawable: Drawable): Bitmap {
    return if (drawable is BitmapDrawable) {
      drawable.bitmap
    } else {
      val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
      val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
      val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      val canvas = Canvas(bitmap)
      drawable.setBounds(0, 0, canvas.width, canvas.height)
      drawable.draw(canvas)
      bitmap
    }
  }

  // VPN permission flow
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
        if (pendingAllowedApps.isNotEmpty()) putStringArrayListExtra(DnsVpnService.EXTRA_ALLOWED_APPS, pendingAllowedApps)
        if (pendingBlockedApps.isNotEmpty()) putStringArrayListExtra(DnsVpnService.EXTRA_BLOCKED_APPS, pendingBlockedApps)
        pendingPerAppMode?.let { putExtra("perAppMode", it) }
        putExtra("useLocalBlocklist", pendingUseLocalBlocklist)
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
