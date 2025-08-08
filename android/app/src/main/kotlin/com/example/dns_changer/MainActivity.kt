// MainActivity.kt
package com.example.dns_changer

import android.app.Activity
import android.content.Intent
import android.net.VpnService
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

          // Read optional queryMethod (int) and port overrides
          // Expected mapping: 0=UDP, 1=TCP, 2=HTTPS(DoH binary), 3=TLS(DoT), 4=HTTPS_JSON
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
          }.also(::startService)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun prepareVpn() {
    // VpnService.prepare returns an Intent? when null, permission already granted.
    val vpnIntent: Intent? = VpnService.prepare(this)
    if (vpnIntent != null) {
      // permission needed
      startActivityForResult(vpnIntent, VPN_REQUEST)
    } else {
      // already have permission, proceed
      onActivityResult(VPN_REQUEST, Activity.RESULT_OK, null)
    }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == VPN_REQUEST && resultCode == Activity.RESULT_OK) {
      Intent(this, DnsVpnService::class.java).apply {
        action = DnsVpnService.ACTION_START
        putExtra("dns1", pendingDns1)
        putExtra("dns2", pendingDns2)
        putExtra("queryMethod", pendingQueryMethod)
        putExtra("port1", pendingPort1)
        putExtra("port2", pendingPort2)
      }.also(::startService)
    } else {
      Log.e("MainActivity", "VPN permission denied or wrong requestCode")
    }
  }
}
