
package com.example.dns_changer.provider

import android.os.ParcelFileDescriptor
import com.example.dns_changer.DnsVpnService
import org.pcap4j.packet.*
import org.pcap4j.packet.namednumber.UdpPort
import org.minidns.dnsmessage.DnsMessage
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Inet4Address
import java.net.Inet6Address
import java.util.*
import android.util.Log
import kotlin.collections.ArrayDeque

abstract class Provider(
    protected val descriptor: ParcelFileDescriptor,
    protected val service: DnsVpnService
) {
    @Volatile
    protected var running = false

    private val deviceWrites: ArrayDeque<ByteArray> = ArrayDeque()

    fun start() { running = true }
    fun shutdown() { running = false }

    /**
     * Main provider loop — implement per-protocol in subclasses.
     */
    abstract fun process()

    /**
     * Subclasses must implement this to handle outgoing DNS requests read from the TUN.
     */
    protected abstract fun handleDnsRequest(packetData: ByteArray)

    protected fun writeToDevice(out: FileOutputStream) {
        val pkt = synchronized(deviceWrites) { if (deviceWrites.isNotEmpty()) deviceWrites.removeFirst() else null }
        pkt?.let {
            try { out.write(it) } catch (_: Exception) { /* ignore */ }
        }
    }

    protected fun queueDeviceWrite(raw: ByteArray) {
        synchronized(deviceWrites) { deviceWrites.addLast(raw) }
    }

    protected fun readDevice(input: FileInputStream, buffer: ByteArray): Int {
        return try {
            input.read(buffer)
        } catch (e: Exception) {
            -1
        }
    }

    // ---------------------------
    // Simple blocklist logic (example)
    // ---------------------------
      // ---------------------------
    // Blocklist logic (improved)
    // ---------------------------
    private val builtinBlocked = setOf("facebook.com", "snapchat.com")

    fun shouldBlock(dnsMsg: DnsMessage): Boolean {
        val q = dnsMsg.question?.name?.toString() ?: return false
        val host = q.trimEnd('.').lowercase()
Log.i("Provider", "shouldBlock check for host=$host useLocalBlock=${service.useLocalBlocklist}")

    
        try {
            if (service.useLocalBlocklist) {
                val set = service.getLocalBlocklist()
                Log.i("Provider", "question=$host localListSize=${set.size}")
                if (set.contains(host)) {
                    Log.i("Provider", "BLOCK exact match $host")
                    return true
                }
                for (entry in set) {
                    if (entry.isEmpty()) continue
                    if (entry.startsWith("*")) {
                        val suffix = entry.removePrefix("*").trimStart('.')
                        if (host == suffix || host.endsWith(".$suffix")) {
                            Log.i("Provider", "BLOCK wildcard $entry matches $host")
                            return true
                        }
                    } else if (entry.startsWith(".")) {
                        val suffix = entry.trimStart('.')
                        if (host == suffix || host.endsWith(".$suffix")) {
                            Log.i("Provider", "BLOCK leading-dot $entry matches $host")
                            return true
                        }
                    } else {
                        if (host == entry || host.endsWith(".$entry")) {
                            Log.i("Provider", "BLOCK suffix match $entry -> $host")
                            return true
                        }
                    }
                }
                return false
            } else {
                // fallback to builtin list (if any)
                return builtinBlocked.any { host == it || host.endsWith(".$it") }
            }
        } catch (e: Exception) {
            Log.w("Provider", "shouldBlock error: ${e.message}")
            return false
        }
    }
    

/**
 * Return true if there are queued writes waiting to be written to the TUN device.
 * Used by providers so they can request POLLOUT when polling the TUN fd.
 */
    protected fun hasQueuedWrites(): Boolean = deviceWrites.isNotEmpty()

    /**
     * Convert upstream DNS response bytes into an IP/UDP packet and queue it for writing to the TUN.
     */
    fun handleDnsResponse(requestPacket: IpPacket, responsePayload: ByteArray) {
        try {
            val udpReq = requestPacket.payload as? UdpPacket ?: return

            val payloadBuilder = UnknownPacket.Builder().rawData(responsePayload)

            val udpBuilder = UdpPacket.Builder(udpReq)
                .srcPort(udpReq.header.dstPort)
                .dstPort(udpReq.header.srcPort)
                .srcAddr(requestPacket.header.dstAddr)
                .dstAddr(requestPacket.header.srcAddr)
                .payloadBuilder(payloadBuilder)
                .correctChecksumAtBuild(true)
                .correctLengthAtBuild(true)

            val ipOut: IpPacket = when (requestPacket) {
                is IpV4Packet -> {
                    IpV4Packet.Builder(requestPacket)
                        .srcAddr(requestPacket.header.dstAddr as Inet4Address)
                        .dstAddr(requestPacket.header.srcAddr as Inet4Address)
                        .payloadBuilder(udpBuilder)
                        .correctChecksumAtBuild(true)
                        .correctLengthAtBuild(true)
                        .build()
                }
                is IpV6Packet -> {
                    IpV6Packet.Builder(requestPacket)
                        .srcAddr(requestPacket.header.dstAddr as Inet6Address)
                        .dstAddr(requestPacket.header.srcAddr as Inet6Address)
                        .payloadBuilder(udpBuilder)
                        .correctLengthAtBuild(true)
                        .build()
                }
                else -> return
            }

            queueDeviceWrite(ipOut.rawData)
        } catch (e: Exception) {
            // ignore or log if you add a logger
        }
    }
}



















