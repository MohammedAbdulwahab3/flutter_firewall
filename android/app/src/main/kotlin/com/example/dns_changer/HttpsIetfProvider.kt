package com.example.dns_changer.provider

//import android.os.FileDescriptor
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import com.example.dns_changer.DnsVpnService
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.minidns.dnsmessage.DnsMessage
import org.pcap4j.packet.IpPacket
import org.pcap4j.packet.IpSelector
import org.pcap4j.packet.UdpPacket
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileDescriptor
import java.util.*
import java.util.concurrent.TimeUnit

class HttpsIetfProvider(
    descriptor: ParcelFileDescriptor,
    service: DnsVpnService
) : Provider(descriptor, service) {

    companion object {
        private const val TAG = "HttpsIetfProvider"
    }

    private val whqList = WhqList()
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .writeTimeout(8, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val req = chain.request().newBuilder()
                .header("Accept", "application/dns-message")
                .build()
            chain.proceed(req)
        }.build()

    private var mInterruptFd: FileDescriptor? = null
    private var mBlockFd: FileDescriptor? = null

    override fun process() {
        try {
            val pipes = Os.pipe()
            mInterruptFd = pipes[0]
            mBlockFd = pipes[1]
        } catch (e: Exception) {
            Log.w(TAG, "pipe failed: ${e.message}")
        }

        val tunFd = descriptor.fileDescriptor
        val input = FileInputStream(tunFd)
        val output = FileOutputStream(tunFd)
        val packetBuf = ByteArray(32767)

        try {
            while (running) {
                val deviceFd = StructPollfd().apply {
                    fd = input.fd
                    events = OsConstants.POLLIN.toShort()
                    if (hasQueuedWrites()) {
                        events = (events.toInt() or OsConstants.POLLOUT).toShort()
                    }
                    revents = 0
                }
                val blockFd = StructPollfd().apply {
                    fd = mBlockFd
                    events = (OsConstants.POLLHUP or OsConstants.POLLERR).toShort()
                    revents = 0
                }

                val polls = ArrayList<StructPollfd>(2)
                polls.add(deviceFd)
                polls.add(blockFd)

                try {
                    Os.poll(polls.toTypedArray(), 1000)
                } catch (e: Exception) {
                    Log.w(TAG, "poll fail: ${e.message}")
                }

                if (blockFd.revents.toInt() != 0) {
                    Log.i(TAG, "Told to stop (blockFd)")
                    running = false
                    return
                }

                val iter = whqList.iterator()
                while (iter.hasNext()) {
                    val w = iter.next()
                    if (w.completed) {
                        try {
                            handleDnsResponse(w.packet, w.result)
                        } catch (e: Exception) {
                            Log.w(TAG, "handleDnsResponse error: ${e.message}")
                        } finally {
                            iter.remove()
                        }
                    }
                }

                try {
                    if ((deviceFd.revents.toInt() and OsConstants.POLLOUT) != 0) {
                        writeToDevice(output)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "writeToDevice error: ${e.message}")
                }

                try {
                    if ((deviceFd.revents.toInt() and OsConstants.POLLIN) != 0) {
                        readDevice(input, packetBuf)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "readDevice error: ${e.message}")
                }
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
            try { output.close() } catch (_: Exception) {}
            whqList.clear()
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

        try { Log.d(TAG, "DoH query ${question.name}") } catch (_: Exception) {}

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

        val upstreamRaw = service.upstream1.trim()
        val httpUrl = if (upstreamRaw.contains("/")) {
            ("https://$upstreamRaw").toHttpUrlOrNull()
        } else {
            ("https://$upstreamRaw/dns-query").toHttpUrlOrNull()
        }

        if (httpUrl == null) {
            Log.w(TAG, "Invalid DoH URL: $upstreamRaw")
            // fallback: return original query bytes (no modification)
            val w = object : WaitingHttpsRequest(ip) {
                init { result = raw; completed = true }
                override fun doRequest() {}
            }
            whqList.add(w)
            return
        }

        whqList.add(object : WaitingHttpsRequest(ip) {
            override fun doRequest() {
                try {
                    val mediaType = "application/dns-message".toMediaType()
                    val body = raw.toRequestBody(mediaType)
                    val req = Request.Builder()
                        .url(httpUrl)
                        .post(body)
                        .header("Accept", "application/dns-message")
                        .header("Content-Type", "application/dns-message")
                        .header("Host", httpUrl.host)
                        .build()

                    httpClient.newCall(req).enqueue(object : Callback {
                        override fun onFailure(call: Call, e: java.io.IOException) {
                            result = raw
                            completed = true
                        }

                        override fun onResponse(call: Call, response: Response) {
                            response.use {
                                try {
                                    if (!it.isSuccessful) {
                                        result = raw
                                        completed = true
                                        return
                                    }
                                    val bytes = it.body?.bytes()
                                    if (bytes != null && bytes.isNotEmpty()) {
                                        result = bytes
                                    } else {
                                        result = raw
                                    }
                                } catch (ex: Exception) {
                                    result = raw
                                } finally {
                                    completed = true
                                }
                            }
                        }
                    })
                } catch (ex: Exception) {
                    result = raw
                    completed = true
                }
            }
        })
    }

    protected open class WaitingHttpsRequest(val packet: IpPacket) {
        @Volatile var completed = false
        @Volatile var result: ByteArray = ByteArray(0)
        open fun doRequest() {}
    }

    protected class WhqList : Iterable<WaitingHttpsRequest> {
        private val list = LinkedList<WaitingHttpsRequest>()
        @Synchronized fun add(r: WaitingHttpsRequest) {
            list.add(r)
            try { r.doRequest() } catch (e: Exception) { Log.w(TAG, "doRequest failed: ${e.message}") }
        }
        @Synchronized override fun iterator(): MutableIterator<WaitingHttpsRequest> = list.iterator()
        @Synchronized fun clear() = list.clear()
    }
}
