package com.example.dns_changer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            try {
                val svcIntent = Intent(context, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_START
                    // You can pass saved config via SharedPreferences if you need to restore settings
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(svcIntent)
                } else {
                    context.startService(svcIntent)
                }
                Log.i("BootReceiver", "Requested service start at boot")
            } catch (e: Exception) {
                Log.w("BootReceiver", "Failed to start VPN on boot: ${e.message}")
            }
        }
    }
}
