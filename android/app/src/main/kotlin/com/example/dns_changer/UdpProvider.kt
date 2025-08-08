package com.example.dns_changer.provider

//import android.os.FileDescriptor
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import com.example.dns_changer.DnsVpnService
import org.minidns.dnsmessage.DnsMessage
import org.pcap4j.packet.IpPacket
import org.pcap4j.packet.IpSelector
import org.pcap4j.packet.UdpPacket
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileDescriptor
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.*

class UdpProvider(
    descriptor: ParcelFileDescriptor,
    service: DnsVpnService
) : Provider(descriptor, service) {

    private val dnsIn = WospList()

    private var mInterruptFd: FileDescriptor? = null
    private var mBlockFd: FileDescriptor? = null

    override fun process() {
        try {
            val pipes = Os.pipe()
            mInterruptFd = pipes[0]
            mBlockFd = pipes[1]
        } catch (e: Exception) {
            Log.w("UdpProvider", "Os.pipe failed: ${e.message}")
        }

        val tunFd = descriptor.fileDescriptor
        val input = FileInputStream(tunFd)
        val output = FileOutputStream(tunFd)
        val packetBuf = ByteArray(32767)

        try {
            while (running) {
                val deviceFd = StructPollfd().apply {
                    fd = input.fd as FileDescriptor
                    events = OsConstants.POLLIN.toShort()
                    revents = 0
                }

                val blockFd = StructPollfd().apply {
                    fd = mBlockFd
                    events = (OsConstants.POLLHUP or OsConstants.POLLERR).toShort()
                    revents = 0
                }

                val polls = ArrayList<StructPollfd>(2 + dnsIn.size())
                polls.add(deviceFd)
                polls.add(blockFd)
                dnsIn.forEach { polls.add(it.sp) }

                if (hasQueuedWrites()) {
                    deviceFd.events = (deviceFd.events.toInt() or OsConstants.POLLOUT).toShort()
                }

                for (p in polls) { p.revents = 0 }

                try {
                    Os.poll(polls.toTypedArray(), 1000)
                } catch (e: Exception) {
                    Log.w("UdpProvider", "Os.poll failed: ${e.message}")
                }

                if (blockFd.revents.toInt() != 0) {
                    Log.i("UdpProvider", "Told to stop VPN (blockFd)")
                    running = false
                    return
                }

                val it = dnsIn.iterator()
                while (it.hasNext()) {
                    val w = it.next()
                    val re = w.sp.revents.toInt()
                    if ((re and OsConstants.POLLIN) != 0) {
                        try {
                            handleRawDnsResponse(w)
                        } catch (e: Exception) {
                            Log.w("UdpProvider", "handleRawDnsResponse error: ${e.message}")
                        } finally {
                            try { w.socket.close() } catch (_: Exception) {}
                            try { w.pfd.close() } catch (_: Exception) {}
                         //   try { it.remove() } catch (_: Exception) {}
                        }
                    } else if ((re and (OsConstants.POLLERR or OsConstants.POLLHUP)) != 0) {
                        try { w.socket.close() } catch (_: Exception) {}
                        try { w.pfd.close() } catch (_: Exception) {}
                       // try { it.remove() } catch (_: Exception) {}
                    }
                }

                try {
                    if ((deviceFd.revents.toInt() and OsConstants.POLLOUT) != 0) {
                        writeToDevice(output)
                    }
                } catch (e: Exception) {
                    Log.w("UdpProvider", "writeToDevice error: ${e.message}")
                }

                try {
                    if ((deviceFd.revents.toInt() and OsConstants.POLLIN) != 0) {
                        val len = readDevice(input, packetBuf)
                        if (len > 0) {
                            val readPacket = packetBuf.copyOfRange(0, len)
                            handleDnsRequest(readPacket)
                        }
                    }
                } catch (e: Exception) {
                    Log.w("UdpProvider", "readDevice error: ${e.message}")
                }
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
            try { output.close() } catch (_: Exception) {}
            dnsIn.forEach {
                try { it.socket.close() } catch (_: Exception) {}
                try { it.pfd.close() } catch (_: Exception) {}
            }
            dnsIn.clear()
            try { if (mInterruptFd != null) Os.close(mInterruptFd) } catch (_: Exception) {}
            try { if (mBlockFd != null) Os.close(mBlockFd) } catch (_: Exception) {}
        }
    }

    override fun handleDnsRequest(packetData: ByteArray) {
        val ip = try {
            IpSelector.newPacket(packetData, 0, packetData.size) as IpPacket
        } catch (e: Exception) { return }
    
        val udp = ip.payload as? UdpPacket ?: return
    
        val dstPort = try { udp.header.dstPort.valueAsInt() } catch (e: Exception) { return }
    
        val raw = udp.payload?.rawData ?: return
    
        val dnsMsg = try { DnsMessage(raw) } catch (e: Exception) { /* not DNS payload, still attempt forwarding below */ null }
    
        val question = try { dnsMsg?.question } catch (e: Exception) { null }
    
        // If it's a DNS query (UDP port 53), handle using existing DNS logic (blocklist, DoH forwarding, etc.)
        if (dstPort == 53 && question != null) {
            try { Log.d("UdpProvider", "DNS query for: ${question.name} type=${question.type}") } catch (_: Exception) {}
    
            if (service.resolveLocal(ip, dnsMsg!!)) return
    
            if (shouldBlock(dnsMsg)) {
                Log.i("UdpProvider", "Blocked DNS: ${question.name}")
                try {
                    val nx = raw.copyOf()
                    val flags = 0x8003
                    nx[2] = ((flags shr 8) and 0xFF).toByte()
                    nx[3] = (flags and 0xFF).toByte()
                    handleDnsResponse(ip, nx)
                } catch (e: Exception) {
                    Log.w("UdpProvider", "Craft NX failed: ${e.message}")
                }
                return
            }
    
            // Existing DNS forwarding over UDP to upstream1 (same as before)
            try {
                val sock = DatagramSocket()
                val protected = try { service.protect(sock) } catch (ex: Exception) { Log.w("UdpProvider","protect threw: ${ex.message}"); false }
                if (!protected) {
                    Log.e("UdpProvider", "Failed to protect socket — replies won't be delivered. Closing socket.")
                    try { sock.close() } catch (_: Exception) {}
                    return
                }
    
                sock.soTimeout = 0
                val addr = InetAddress.getByName(service.upstream1)
                val out = DatagramPacket(raw, raw.size, addr, service.port1)
    
                Log.d("UdpProvider", "Sending DNS query to ${addr.hostAddress}:${service.port1} for ${question.name}")
                sock.send(out)
                Log.d("UdpProvider", "Sent packet (length=${out.length}) to ${addr.hostAddress}:${service.port1}")
    
                val pfd = try {
                    ParcelFileDescriptor.fromDatagramSocket(sock)
                } catch (e: Exception) {
                    Log.w("UdpProvider", "fromDatagramSocket failed: ${e.message}")
                    try { sock.close() } catch (_: Exception) {}
                    return
                }
    
                val sp = StructPollfd().apply {
                    fd = pfd.fileDescriptor
                    events = OsConstants.POLLIN.toShort()
                    revents = 0
                }
    
                dnsIn.add(WaitingOnSocketPacket(sock, ip, pfd, sp))
            } catch (e: Exception) {
                Log.w("UdpProvider", "Forward error: ${e.message}")
            }
    
            return
        }
    
        // ---------- Non-DNS UDP forwarding (NEW) ----------
        // For UDP packets not destined to port 53, forward payload using a protected DatagramSocket.
        try {
            val sock = DatagramSocket()
            val protected = try { service.protect(sock) } catch (ex: Exception) { Log.w("UdpProvider","protect threw: ${ex.message}"); false }
            if (!protected) {
                Log.e("UdpProvider", "Failed to protect socket for UDP forwarding. Closing socket.")
                try { sock.close() } catch (_: Exception) {}
                return
            }
    
            sock.soTimeout = 0
    
            val dstAddr = when (ip) {
                is org.pcap4j.packet.IpV4Packet -> ip.header.dstAddr as InetAddress
                is org.pcap4j.packet.IpV6Packet -> ip.header.dstAddr as InetAddress
                else -> null
            } ?: return
    
            val out = DatagramPacket(raw, raw.size, dstAddr, dstPort)
            Log.d("UdpProvider", "Forwarding UDP to ${dstAddr.hostAddress}:$dstPort (len=${raw.size})")
            sock.send(out)
    
            val pfd = try {
                ParcelFileDescriptor.fromDatagramSocket(sock)
            } catch (e: Exception) {
                Log.w("UdpProvider", "fromDatagramSocket failed: ${e.message}")
                try { sock.close() } catch (_: Exception) {}
                return
            }
    
            val sp = StructPollfd().apply {
                fd = pfd.fileDescriptor
                events = OsConstants.POLLIN.toShort()
                revents = 0
            }
    
            // Reuse WaitingOnSocketPacket to capture the reply and map it back to the original IP packet.
            dnsIn.add(WaitingOnSocketPacket(sock, ip, pfd, sp))
        } catch (e: Exception) {
            Log.w("UdpProvider", "UDP forward error: ${e.message}")
        }
    }
    


    // override fun handleDnsRequest(packetData: ByteArray) {
    //     val ip = try {
    //         IpSelector.newPacket(packetData, 0, packetData.size) as IpPacket
    //     } catch (e: Exception) { return }

    //     val udp = ip.payload as? UdpPacket ?: return

    //     val dstPort = try { udp.header.dstPort.valueAsInt() } catch (e: Exception) { return }
    //     if (dstPort != 53) return

    //     val raw = udp.payload?.rawData ?: return

    //     val dnsMsg = try { DnsMessage(raw) } catch (e: Exception) { return }
    //     val question = try { dnsMsg.question } catch (e: Exception) { return }
    //     if (question == null) return

    //     try { Log.d("UdpProvider", "DNS query for: ${question.name} type=${question.type}") } catch (_: Exception) {}

    //     if (service.resolveLocal(ip, dnsMsg)) return

    //     if (shouldBlock(dnsMsg)) {
    //         Log.i("UdpProvider", "Blocked DNS: ${question.name}")
    //         try {
    //             val nx = raw.copyOf()
    //             val flags = 0x8003
    //             nx[2] = ((flags shr 8) and 0xFF).toByte()
    //             nx[3] = (flags and 0xFF).toByte()
    //             handleDnsResponse(ip, nx)
    //         } catch (e: Exception) {
    //             Log.w("UdpProvider", "Craft NX failed: ${e.message}")
    //         }
    //         return
    //     }

    //     try {
    //         val sock = DatagramSocket()
    //         val protected = try { service.protect(sock) } catch (ex: Exception) { Log.w("UdpProvider","protect threw: ${ex.message}"); false }
    //         if (!protected) {
    //             Log.e("UdpProvider", "Failed to protect socket — replies won't be delivered. Closing socket.")
    //             try { sock.close() } catch (_: Exception) {}
    //             return
    //         }

    //         sock.soTimeout = 0
    //         val addr = InetAddress.getByName(service.upstream1)
    //         val out = DatagramPacket(raw, raw.size, addr, service.port1)

    //         Log.d("UdpProvider", "Sending DNS query to ${addr.hostAddress}:${service.port1} for ${question.name}")
    //         sock.send(out)
    //         Log.d("UdpProvider", "Sent packet (length=${out.length}) to ${addr.hostAddress}:${service.port1}")

    //         val pfd = try {
    //             ParcelFileDescriptor.fromDatagramSocket(sock)
    //         } catch (e: Exception) {
    //             Log.w("UdpProvider", "fromDatagramSocket failed: ${e.message}")
    //             try { sock.close() } catch (_: Exception) {}
    //             return
    //         }

    //         val sp = StructPollfd().apply {
    //             fd = pfd.fileDescriptor
    //             events = OsConstants.POLLIN.toShort()
    //             revents = 0
    //         }

    //         dnsIn.add(WaitingOnSocketPacket(sock, ip, pfd, sp))
    //     } catch (e: Exception) {
    //         Log.w("UdpProvider", "Forward error: ${e.message}")
    //     }
    // }

    private fun handleRawDnsResponse(w: WaitingOnSocketPacket) {
        try {
            val buf = ByteArray(4096)
            val reply = DatagramPacket(buf, buf.size)
            w.socket.receive(reply)
            Log.d("UdpProvider", "Received DNS reply from ${reply.address?.hostAddress} length=${reply.length}")
            val respBytes = reply.data.copyOf(reply.length)
            handleDnsResponse(w.packet, respBytes)
        } catch (e: Exception) {
            Log.w("UdpProvider", "Receive error: ${e.message}")
        }
    }

    private data class WaitingOnSocketPacket(
        val socket: DatagramSocket,
        val packet: IpPacket,
        val pfd: ParcelFileDescriptor,
        val sp: StructPollfd,
        private val createdAt: Long = System.currentTimeMillis()
    ) {
        fun ageSeconds(): Long = (System.currentTimeMillis() - createdAt) / 1000
    }

    private class WospList : Iterable<WaitingOnSocketPacket> {
        private val list = LinkedList<WaitingOnSocketPacket>()

        @Synchronized
        fun add(wosp: WaitingOnSocketPacket) {
            try {
                if (list.size > 1024) {
                    Log.d("UdpProvider", "Dropping socket due to space constraints: ${list[0].socket}")
                    try { list[0].socket.close() } catch (_: Exception) {}
                    try { list.removeAt(0) } catch (_: Exception) {}
                }
                while (list.isNotEmpty() && list[0].ageSeconds() > 10) {
                    Log.d("UdpProvider", "Timeout on socket ${list[0].socket}")
                    try { list[0].socket.close() } catch (_: Exception) {}
                    try { list.removeAt(0) } catch (_: Exception) {}
                }
                list.add(wosp)
            } catch (e: Exception) {
                Log.w("UdpProvider", "WospList.add exception: ${e.message}")
            }
        }

        @Synchronized
        override fun iterator(): Iterator<WaitingOnSocketPacket> = list.iterator()

        @Synchronized
        fun size(): Int = list.size

        @Synchronized
        fun forEach(action: (WaitingOnSocketPacket) -> Unit) {
            for (w in list) action(w)
        }

        @Synchronized
        fun clear() { list.clear() }
    }
}
