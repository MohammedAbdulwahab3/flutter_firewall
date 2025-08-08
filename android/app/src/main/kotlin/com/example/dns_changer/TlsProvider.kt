// package com.example.dns_changer.provider

// import android.os.ParcelFileDescriptor
// import android.system.Os
// import android.system.OsConstants
// import android.system.StructPollfd
// import android.util.Log
// import com.example.dns_changer.DnsVpnService
// import org.minidns.dnsmessage.DnsMessage
// import org.pcap4j.packet.IpPacket
// import org.pcap4j.packet.IpSelector
// import org.pcap4j.packet.UdpPacket
// import java.io.DataInputStream
// import java.io.DataOutputStream
// import java.io.FileDescriptor
// import java.io.FileInputStream
// import java.io.FileOutputStream
// import java.net.InetAddress
// import java.net.Socket
// import java.util.*
// import javax.net.ssl.SSLContext

// class TlsProvider(
//     descriptor: ParcelFileDescriptor,
//     service: DnsVpnService
// ) : Provider(descriptor, service) {

//     private val dnsIn = WospList()
//     private var mInterruptFd: FileDescriptor? = null
//     private var mBlockFd: FileDescriptor? = null
//     private val TAG = "TlsProvider"

//     override fun process() {
//         try {
//             val pipes = Os.pipe()
//             mInterruptFd = pipes[0]
//             mBlockFd = pipes[1]
//         } catch (e: Exception) {
//             Log.w(TAG, "pipe failed: ${e.message}")
//         }

//         val tunFd = descriptor.fileDescriptor
//         val input = FileInputStream(tunFd)
//         val output = FileOutputStream(tunFd)
//         val packetBuf = ByteArray(32767)

//         try {
//             while (running) {
//                 val deviceFd = StructPollfd().apply {
//                     fd = input.fd
//                     events = OsConstants.POLLIN.toShort()
//                     if (hasQueuedWrites()) {
//                         events = (events.toInt() or OsConstants.POLLOUT).toShort()
//                     }
//                     revents = 0
//                 }

//                 val blockFd = StructPollfd().apply {
//                     fd = mBlockFd
//                     events = (OsConstants.POLLHUP or OsConstants.POLLERR).toShort()
//                     revents = 0
//                 }

//                 val polls = ArrayList<StructPollfd>(2 + dnsIn.size())
//                 polls.add(deviceFd)
//                 polls.add(blockFd)
//                 for (w in dnsIn) polls.add(w.sp)

//                 try {
//                     Os.poll(polls.toTypedArray(), 1000)
//                 } catch (e: Exception) {
//                     Log.w(TAG, "poll error: ${e.message}")
//                 }

//                 if (blockFd.revents.toInt() != 0) {
//                     Log.i(TAG, "Told to stop (blockFd)")
//                     running = false
//                     return
//                 }

//                 val iter = dnsIn.iterator()
//                 while (iter.hasNext()) {
//                     val w = iter.next()
//                     val re = w.sp.revents.toInt()
//                     if ((re and OsConstants.POLLIN) != 0) {
//                         try {
//                             handleRawTlsResponse(w)
//                         } catch (e: Exception) {
//                             Log.w(TAG, "handleRawTlsResponse: ${e.message}")
//                         } finally {
//                             try { w.socket.close() } catch (_: Exception) {}
//                             try { w.pfd.close() } catch (_: Exception) {}
//                       //      try { iter.remove() } catch (_: Exception) {}
//                         }
//                     } else if ((re and (OsConstants.POLLERR or OsConstants.POLLHUP)) != 0) {
//                         try { w.socket.close() } catch (_: Exception) {}
//                         try { w.pfd.close() } catch (_: Exception) {}
//                       //  try { iter.remove() } catch (_: Exception) {}
//                     }
//                 }

//                 try {
//                     if ((deviceFd.revents.toInt() and OsConstants.POLLOUT) != 0) {
//                         writeToDevice(output)
//                     }
//                 } catch (e: Exception) {
//                     Log.w(TAG, "writeToDevice error: ${e.message}")
//                 }

//                 try {
//                     if ((deviceFd.revents.toInt() and OsConstants.POLLIN) != 0) {
//                         readDevice(input, packetBuf)
//                     }
//                 } catch (e: Exception) {
//                     Log.w(TAG, "readDevice error: ${e.message}")
//                 }
//             }
//         } finally {
//             try { input.close() } catch (_: Exception) {}
//             try { output.close() } catch (_: Exception) {}
//             dnsIn.forEach {
//                 try { it.socket.close() } catch (_: Exception) {}
//                 try { it.pfd.close() } catch (_: Exception) {}
//             }
//             dnsIn.clear()
//             try { if (mInterruptFd != null) Os.close(mInterruptFd) } catch (_: Exception) {}
//             try { if (mBlockFd != null) Os.close(mBlockFd) } catch (_: Exception) {}
//         }
//     }

//     override fun handleDnsRequest(packetData: ByteArray) {
//         val ip = try {
//             IpSelector.newPacket(packetData, 0, packetData.size) as IpPacket
//         } catch (e: Exception) { return }

//         val udp = ip.payload as? UdpPacket ?: return

//         val dstPort = try { udp.header.dstPort.valueAsInt() } catch (e: Exception) { return }
//         if (dstPort != 53) return

//         val raw = udp.payload?.rawData ?: return
//         val dnsMsg = try { DnsMessage(raw) } catch (e: Exception) { return }
//         val question = try { dnsMsg.question } catch (e: Exception) { return }
//         if (question == null) return

//         try { Log.d(TAG, "DoT query for: ${question.name}") } catch (_: Exception) {}

//         if (service.resolveLocal(ip, dnsMsg)) return
//         if (shouldBlock(dnsMsg)) {
//             try {
//                 val nx = raw.copyOf()
//                 val flags = 0x8003
//                 nx[2] = ((flags shr 8) and 0xFF).toByte()
//                 nx[3] = (flags and 0xFF).toByte()
//                 handleDnsResponse(ip, nx)
//             } catch (e: Exception) {
//                 Log.w(TAG, "craft NX failed: ${e.message}")
//             }
//             return
//         }

//         try {
//             val host = service.upstream1.trim()
//             val port = service.port1

//             val sslCtx = SSLContext.getInstance("TLS")
//             sslCtx.init(null, null, null)
//             val factory = sslCtx.socketFactory

//             // Create an unconnected socket and connect using host so SNI works
//             val tlsSocket = factory.createSocket() as Socket
//             tlsSocket.connect(java.net.InetSocketAddress(host, port), 8000)

//             val protected = try { service.protect(tlsSocket) } catch (ex: Exception) { Log.w(TAG, "protect threw: ${ex.message}"); false }
//             if (!protected) {
//                 Log.e(TAG, "Failed to protect TLS socket; closing")
//                 try { tlsSocket.close() } catch (_: Exception) {}
//                 return
//             }

//             tlsSocket.soTimeout = 0

//             val dos = DataOutputStream(tlsSocket.getOutputStream())
//             dos.writeShort(raw.size)
//             dos.write(raw)
//             dos.flush()

//             val pfd = try { ParcelFileDescriptor.fromSocket(tlsSocket) } catch (e: Exception) {
//                 try { tlsSocket.close() } catch (_: Exception) {}
//                 Log.w(TAG, "fromSocket failed: ${e.message}")
//                 return
//             }
//             val sp = StructPollfd().apply {
//                 fd = pfd.fileDescriptor
//                 events = OsConstants.POLLIN.toShort()
//                 revents = 0
//             }
//             dnsIn.add(WaitingOnSocketPacket(tlsSocket, ip, pfd, sp))
//         } catch (e: Exception) {
//             Log.w(TAG, "DoT forward error: ${e.message}")
//         }
//     }

//     private fun handleRawTlsResponse(w: WaitingOnSocketPacket) {
//         try {
//             val inStream = DataInputStream(w.socket.getInputStream())
//             val length = try { inStream.readUnsignedShort() } catch (e: Exception) { return }
//             if (length <= 0) return
//             val data = ByteArray(length)
//             inStream.readFully(data)
//             handleDnsResponse(w.packet, data)
//         } catch (e: Exception) {
//             Log.w(TAG, "read tls response: ${e.message}")
//         }
//     }

//     private data class WaitingOnSocketPacket(
//         val socket: Socket,
//         val packet: IpPacket,
//         val pfd: ParcelFileDescriptor,
//         val sp: StructPollfd,
//         val createdAt: Long = System.currentTimeMillis()
//     ) {
//         fun ageSeconds(): Long = (System.currentTimeMillis() - createdAt) / 1000
//     }

//     private class WospList : Iterable<WaitingOnSocketPacket> {
//         private val list = LinkedList<WaitingOnSocketPacket>()

//         @Synchronized
//         fun add(wosp: WaitingOnSocketPacket) {
//             try {
//                 if (list.size > 1024) {
//                     try { list[0].socket.close() } catch (_: Exception) {}
//                     try { list.removeAt(0) } catch (_: Exception) {}
//                 }
//                 while (list.isNotEmpty() && list[0].ageSeconds() > 10) {
//                     try { list[0].socket.close() } catch (_: Exception) {}
//                     try { list.removeAt(0) } catch (_: Exception) {}
//                 }
//                 list.add(wosp)
//             } catch (e: Exception) {
//                 Log.w("TlsProvider", "WospList.add: ${e.message}")
//             }
//         }

//         @Synchronized
//         override fun iterator(): Iterator<WaitingOnSocketPacket> = list.iterator()
//         @Synchronized fun size(): Int = list.size
//         @Synchronized fun clear() = list.clear()
//     }
// }
package com.example.dns_changer.provider

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
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Socket
import java.util.*
import javax.net.ssl.SSLContext

class TlsProvider(
    descriptor: ParcelFileDescriptor,
    svc: DnsVpnService
) : Provider(descriptor, svc) {


    private val dnsIn = WospList()
    private var mInterruptFd: FileDescriptor? = null
    private var mBlockFd: FileDescriptor? = null
    private val TAG = "TlsProvider"

    override fun process() {
        try {
            val pipes = Os.pipe()
            mInterruptFd = pipes[0]; mBlockFd = pipes[1]
        } catch (e: Exception) { Log.w(TAG, "pipe failed: ${e.message}") }

        val tunFd = descriptor.fileDescriptor
        val input = FileInputStream(tunFd)
        val output = FileOutputStream(tunFd)
        val packetBuf = ByteArray(32767)

        try {
            while (running) {
                val needsPollOut = hasQueuedWrites()
                val deviceFd = StructPollfd().apply {
                    fd = input.fd
                    events = OsConstants.POLLIN.toShort()
                    if (needsPollOut) events = (events.toInt() or OsConstants.POLLOUT).toShort()
                    revents = 0
                }
                val blockFd = StructPollfd().apply {
                    fd = mBlockFd
                    events = (OsConstants.POLLHUP or OsConstants.POLLERR).toShort()
                    revents = 0
                }

                val polls = ArrayList<StructPollfd>(2 + dnsIn.size())
                polls.add(deviceFd); polls.add(blockFd)
                for (w in dnsIn) polls.add(w.sp)

                try { Os.poll(polls.toTypedArray(), 1000) } catch (e: Exception) { Log.w(TAG, "poll error: ${e.message}") }

                if (blockFd.revents.toInt() != 0) {
                    Log.i(TAG, "Told to stop (blockFd)"); running = false; return
                }

                val iter = dnsIn.iterator()
                while (iter.hasNext()) {
                    val w = iter.next()
                    val re = w.sp.revents.toInt()
                    if ((re and OsConstants.POLLIN) != 0) {
                        try { handleRawTlsResponse(w) } catch (e: Exception) { Log.w(TAG, "handleRawTlsResponse: ${e.message}") } finally {
                            try { w.socket.close() } catch (_: Exception) {}
                            try { w.pfd.close() } catch (_: Exception) {}
                       //     iter.remove()
                        }
                    } else if ((re and (OsConstants.POLLERR or OsConstants.POLLHUP)) != 0) {
                        try { w.socket.close() } catch (_: Exception) {}
                        try { w.pfd.close() } catch (_: Exception) {}
                     //   iter.remove()
                    }
                }

                try { if ((deviceFd.revents.toInt() and OsConstants.POLLOUT) != 0) writeToDevice(output) } catch (e: Exception) { Log.w(TAG, "writeToDevice error: ${e.message}") }
                try { if ((deviceFd.revents.toInt() and OsConstants.POLLIN) != 0) readDevice(input, packetBuf) } catch (e: Exception) { Log.w(TAG, "readDevice error: ${e.message}") }
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
            try { output.close() } catch (_: Exception) {}
            dnsIn.forEach { try { it.socket.close() } catch (_: Exception) {}; try { it.pfd.close() } catch (_: Exception) {} }
            dnsIn.clear()
            try { if (mInterruptFd != null) Os.close(mInterruptFd) } catch (_: Exception) {}
            try { if (mBlockFd != null) Os.close(mBlockFd) } catch (_: Exception) {}
        }
    }

    override fun handleDnsRequest(packetData: ByteArray) {
        val ip = try { IpSelector.newPacket(packetData, 0, packetData.size) as IpPacket } catch (e: Exception) { return }
        val udp = ip.payload as? UdpPacket ?: return
        val dstPort = try { udp.header.dstPort.valueAsInt() } catch (e: Exception) { return }
        if (dstPort != 53) return

        val raw = udp.payload?.rawData ?: return
        val dnsMsg = try { DnsMessage(raw) } catch (e: Exception) { return }
        val question = try { dnsMsg.question } catch (e: Exception) { return }
        if (question == null) return

        try { Log.d(TAG, "DoT query for: ${question.name}") } catch (_: Exception) {}

        if (service.resolveLocal(ip, dnsMsg)) return
        if (shouldBlock(dnsMsg)) {
            try {
                val nx = raw.copyOf()
                val flags = 0x8003
                nx[2] = ((flags shr 8) and 0xFF).toByte()
                nx[3] = (flags and 0xFF).toByte()
                handleDnsResponse(ip, nx)
            } catch (e: Exception) { Log.w(TAG, "craft NX failed: ${e.message}") }
            return
        }

        try {
            val host = service.upstream1.trim()
            val port = service.port1

            val sslCtx = SSLContext.getInstance("TLS")
            sslCtx.init(null, null, null)
            val factory = sslCtx.socketFactory

            // Create an unconnected socket, protect BEFORE connect
            val tlsSocket = factory.createSocket() as Socket
            try { service.protect(tlsSocket) } catch (ex: Exception) {
                Log.w(TAG, "protect threw: ${ex.message}")
                try { tlsSocket.close() } catch (_: Exception) {}
                return
            }

            tlsSocket.connect(java.net.InetSocketAddress(host, port), 8000)
            tlsSocket.soTimeout = 0

            val dos = DataOutputStream(tlsSocket.getOutputStream())
            dos.writeShort(raw.size); dos.write(raw); dos.flush()

            val pfd = try { ParcelFileDescriptor.fromSocket(tlsSocket) } catch (e: Exception) {
                try { tlsSocket.close() } catch (_: Exception) {}
                Log.w(TAG, "fromSocket failed: ${e.message}")
                return
            }
            val sp = StructPollfd().apply {
                fd = pfd.fileDescriptor
                events = OsConstants.POLLIN.toShort()
                revents = 0
            }
            dnsIn.add(WaitingOnSocketPacket(tlsSocket, ip, pfd, sp))
        } catch (e: Exception) {
            Log.w(TAG, "DoT forward error: ${e.message}")
        }
    }

    private fun handleRawTlsResponse(w: WaitingOnSocketPacket) {
        try {
            val inStream = DataInputStream(w.socket.getInputStream())
            val length = try { inStream.readUnsignedShort() } catch (e: Exception) { return }
            if (length <= 0) return
            val data = ByteArray(length); inStream.readFully(data)
            handleDnsResponse(w.packet, data)
        } catch (e: Exception) { Log.w(TAG, "read tls response: ${e.message}") }
    }

    private data class WaitingOnSocketPacket(
        val socket: Socket,
        val packet: IpPacket,
        val pfd: ParcelFileDescriptor,
        val sp: StructPollfd,
        val createdAt: Long = System.currentTimeMillis()
    ) {
        fun ageSeconds(): Long = (System.currentTimeMillis() - createdAt) / 1000
    }

    private class WospList : Iterable<WaitingOnSocketPacket> {
        private val list = LinkedList<WaitingOnSocketPacket>()
        @Synchronized fun add(wosp: WaitingOnSocketPacket) {
            try {
                if (list.size > 1024) {
                    try { list[0].socket.close() } catch (_: Exception) {}
                    try { list.removeAt(0) } catch (_: Exception) {}
                }
                while (list.isNotEmpty() && list[0].ageSeconds() > 10) {
                    try { list[0].socket.close() } catch (_: Exception) {}
                    try { list.removeAt(0) } catch (_: Exception) {}
                }
                list.add(wosp)
            } catch (e: Exception){
                //("TlsProvider", "WospList.add: ${e.message}")
            }
             //{ Log.w(TAG, "WospList.add: ${e.message}") }
        }
        @Synchronized override fun iterator(): Iterator<WaitingOnSocketPacket> = list.iterator()
        @Synchronized fun size(): Int = list.size
        @Synchronized fun clear() = list.clear()
    }
}
