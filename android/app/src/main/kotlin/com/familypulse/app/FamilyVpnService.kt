package com.familypulse.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class FamilyVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.familypulse.app.VPN_START"
        const val ACTION_STOP = "com.familypulse.app.VPN_STOP"
        const val ACTION_RELOAD_RULES = "com.familypulse.app.VPN_RELOAD"

        private const val TAG = "FamilyVpnService"
        private const val CHANNEL_ID = "family_pulse_vpn_channel"
        private const val NOTIFICATION_ID = 4041

        // Виртуальный DNS-адрес внутри VPN-туннеля (перехватываем только пакеты на него)
        private const val VPN_ADDRESS = "10.111.222.1"
        private const val VPN_DNS = "10.111.222.2"

        // Апстрим DNS-серверы:
        // 94.140.14.15 — AdGuard Family DNS (блокирует 18+, казино, вредоносные сайты + SafeSearch)
        // 77.88.8.8 — Яндекс.DNS Базовый (если фильтрация 18+ отключена, но работают чёрный/белый списки)
        private const val UPSTREAM_FAMILY_DNS = "94.140.14.15"
        private const val UPSTREAM_STANDARD_DNS = "77.88.8.8"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var workerThread: Thread? = null
    private var dnsExecutor: ExecutorService? = null

    @Volatile
    private var filterEnabled: Boolean = true

    @Volatile
    private var filterMode: String = "blacklist" // "blacklist" или "whitelist"

    @Volatile
    private var blockAdult: Boolean = true

    @Volatile
    private var blockedDomains: Set<String> = emptySet()

    @Volatile
    private var allowedDomains: Set<String> = emptySet()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
            ACTION_RELOAD_RULES -> {
                loadRulesFromPrefs()
                if (!filterEnabled) {
                    stopVpn()
                    return START_NOT_STICKY
                }
                if (!isRunning) {
                    startVpn()
                }
                return START_STICKY
            }
            else -> {
                loadRulesFromPrefs()
                if (!filterEnabled) {
                    stopVpn()
                    return START_NOT_STICKY
                }
                if (!isRunning) {
                    startVpn()
                }
                return START_STICKY
            }
        }
    }

    private fun loadRulesFromPrefs() {
        val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
        filterEnabled = prefs.getBoolean("web_filter_enabled", false)
        filterMode = prefs.getString("web_filter_mode", "blacklist") ?: "blacklist"
        blockAdult = prefs.getBoolean("web_filter_block_adult", true)

        blockedDomains = (prefs.getStringSet("web_filter_blocked", emptySet()) ?: emptySet())
            .map { normalizeDomain(it) }
            .filter { it.isNotEmpty() }
            .toSet()

        allowedDomains = (prefs.getStringSet("web_filter_allowed", emptySet()) ?: emptySet())
            .map { normalizeDomain(it) }
            .filter { it.isNotEmpty() }
            .toSet()
    }

    private fun normalizeDomain(raw: String): String {
        return raw.trim()
            .lowercase()
            .removePrefix("https://")
            .removePrefix("http://")
            .removePrefix("www.")
            .substringBefore("/")
            .substringBefore("?")
            .trimEnd('.')
    }

    private fun startVpn() {
        try {
            startForegroundNotification()

            val builder = Builder()
                .setSession("FamilyPulse Web Filter")
                .addAddress(VPN_ADDRESS, 32)
                .addDnsServer(VPN_DNS)
                // Маршрутизируем ТОЛЬКО DNS-запросы к виртуальному DNS (весь остальной трафик идёт напрямую!)
                .addRoute(VPN_DNS, 32)
                .setMtu(1500)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            // Исключаем само приложение FamilyPulse из VPN, чтобы Firebase всегда имел прямой доступ
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Не удалось исключить пакет из VPN: ${e.message}")
            }

            vpnInterface?.close()
            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e(TAG, "VpnService.Builder.establish() вернул null (нет разрешения VPN)")
                stopSelf()
                return
            }

            isRunning = true
            dnsExecutor = Executors.newCachedThreadPool()

            workerThread = Thread({
                runPacketLoop()
            }, "FamilyVpnWorker").apply { start() }

            Log.i(TAG, "FamilyVpnService успешно запущен (mode=$filterMode, blockAdult=$blockAdult)")
        } catch (e: Exception) {
            Log.e(TAG, "Ошибка запуска VPN: ${e.message}", e)
            stopVpn()
        }
    }

    private fun runPacketLoop() {
        val fd = vpnInterface?.fileDescriptor ?: return
        val inputStream = FileInputStream(fd)
        val outputStream = FileOutputStream(fd)
        val packetBuffer = ByteArray(32767)

        while (isRunning && !Thread.interrupted()) {
            try {
                val length = inputStream.read(packetBuffer)
                if (length <= 0) {
                    Thread.sleep(10)
                    continue
                }

                val packetCopy = packetBuffer.copyOf(length)
                dnsExecutor?.execute {
                    handleIpPacket(packetCopy, outputStream)
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Ошибка чтения TUN-интерфейса: ${e.message}")
                }
                break
            }
        }
    }

    private fun handleIpPacket(ipPacket: ByteArray, outputStream: FileOutputStream) {
        if (ipPacket.size < 28) return

        val version = (ipPacket[0].toInt() shr 4) and 0x0F
        if (version != 4) return // Обрабатываем IPv4 DNS-пакеты

        val ipHeaderLen = (ipPacket[0].toInt() and 0x0F) * 4
        if (ipPacket.size < ipHeaderLen + 8) return

        val protocol = ipPacket[9].toInt() and 0xFF
        if (protocol != 17) return // 17 = UDP

        val srcIp = ipPacket.copyOfRange(12, 16)
        val dstIp = ipPacket.copyOfRange(16, 20)

        val srcPort = ((ipPacket[ipHeaderLen].toInt() and 0xFF) shl 8) or
                (ipPacket[ipHeaderLen + 1].toInt() and 0xFF)
        val dstPort = ((ipPacket[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or
                (ipPacket[ipHeaderLen + 3].toInt() and 0xFF)

        if (dstPort != 53) return // Только DNS-порт 53

        val dnsPayloadOffset = ipHeaderLen + 8
        val dnsPayloadLength = ipPacket.size - dnsPayloadOffset
        if (dnsPayloadLength <= 12) return

        val dnsQuery = ipPacket.copyOfRange(dnsPayloadOffset, ipPacket.size)
        val queriedDomain = extractDomainName(dnsQuery)

        val dnsResponse: ByteArray? = if (queriedDomain != null && isDomainBlocked(queriedDomain)) {
            Log.d(TAG, "Заблокирован домен: $queriedDomain")
            buildNxDomainResponse(dnsQuery)
        } else {
            forwardDnsQuery(dnsQuery)
        }

        if (dnsResponse != null) {
            val responseIpPacket = buildIpv4UdpPacket(
                srcIp = dstIp,
                dstIp = srcIp,
                srcPort = dstPort,
                dstPort = srcPort,
                udpPayload = dnsResponse
            )
            synchronized(outputStream) {
                try {
                    outputStream.write(responseIpPacket)
                } catch (e: Exception) {
                    Log.e(TAG, "Ошибка записи ответа в TUN: ${e.message}")
                }
            }
        }
    }

    private fun isDomainBlocked(rawDomain: String): Boolean {
        val domain = normalizeDomain(rawDomain)
        if (domain.isEmpty()) return false

        // Всегда пропускаем служебные домены Google/Firebase/RuStore для работы самого приложения
        if (domain.endsWith("googleapis.com") ||
            domain.endsWith("firebaseio.com") ||
            domain.endsWith("gstatic.com") ||
            domain.endsWith("rustore.ru")
        ) {
            return false
        }

        return if (filterMode == "whitelist") {
            // В режиме белого списка разрешены только домены из allowedDomains (и их поддомены)
            val isAllowed = allowedDomains.any { allowed ->
                domain == allowed || domain.endsWith(".$allowed")
            }
            !isAllowed
        } else {
            // В режиме чёрного списка блокируем домены из blockedDomains (и их поддомены)
            blockedDomains.any { blocked ->
                domain == blocked || domain.endsWith(".$blocked")
            }
        }
    }

    private fun extractDomainName(dnsPacket: ByteArray): String? {
        try {
            var pos = 12 // Пропускаем 12-байтный DNS-заголовок
            val labels = mutableListOf<String>()
            while (pos < dnsPacket.size) {
                val len = dnsPacket[pos].toInt() and 0xFF
                if (len == 0) break
                if ((len and 0xC0) == 0xC0) break
                pos++
                if (pos + len > dnsPacket.size) return null
                labels.add(String(dnsPacket, pos, len, Charsets.UTF_8))
                pos += len
            }
            return if (labels.isNotEmpty()) labels.joinToString(".") else null
        } catch (_: Exception) {
            return null
        }
    }

    private fun buildNxDomainResponse(query: ByteArray): ByteArray {
        val resp = query.copyOf()
        if (resp.size >= 4) {
            // QR = 1 (ответ), RD = 1, RCODE = 3 (NXDOMAIN — домен не существует)
            resp[2] = ((resp[2].toInt() or 0x80) and 0xFF).toByte()
            resp[3] = ((resp[3].toInt() and 0xF0) or 0x03).toByte()
        }
        return resp
    }

    private fun forwardDnsQuery(dnsQuery: ByteArray): ByteArray? {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            protect(socket) // Защищаем сокет от попадания обратно в VPN-туннель
            socket.soTimeout = 4000

            val upstreamIp = if (blockAdult) UPSTREAM_FAMILY_DNS else UPSTREAM_STANDARD_DNS
            val serverAddr = InetAddress.getByName(upstreamIp)
            val outPacket = DatagramPacket(dnsQuery, dnsQuery.size, serverAddr, 53)
            socket.send(outPacket)

            val inBuf = ByteArray(4096)
            val inPacket = DatagramPacket(inBuf, inBuf.size)
            socket.receive(inPacket)
            return inBuf.copyOf(inPacket.length)
        } catch (e: Exception) {
            Log.w(TAG, "Ошибка апстрим DNS: ${e.message}")
            return null
        } finally {
            socket?.close()
        }
    }

    private fun buildIpv4UdpPacket(
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        udpPayload: ByteArray
    ): ByteArray {
        val udpLength = 8 + udpPayload.size
        val totalLength = 20 + udpLength
        val buffer = ByteBuffer.allocate(totalLength)

        // IPv4 Header (20 байт)
        buffer.put(0x45.toByte()) // Version 4, IHL 5
        buffer.put(0x00.toByte()) // TOS
        buffer.putShort(totalLength.toShort())
        buffer.putShort(0x0000.toShort()) // Identification
        buffer.putShort(0x4000.toShort()) // Flags (Don't Fragment)
        buffer.put(64.toByte()) // TTL
        buffer.put(17.toByte()) // Protocol UDP
        buffer.putShort(0x0000.toShort()) // Checksum placeholder
        buffer.put(srcIp)
        buffer.put(dstIp)

        // Считаем контрольную сумму IPv4 заголовка
        val ipChecksum = calculateIpChecksum(buffer.array(), 0, 20)
        buffer.putShort(10, ipChecksum)

        // UDP Header (8 байт)
        buffer.putShort(srcPort.toShort())
        buffer.putShort(dstPort.toShort())
        buffer.putShort(udpLength.toShort())
        buffer.putShort(0x0000.toShort()) // UDP checksum (опционально для IPv4 = 0)
        buffer.put(udpPayload)

        return buffer.array()
    }

    private fun calculateIpChecksum(buf: ByteArray, offset: Int, length: Int): Short {
        var sum = 0
        var i = offset
        while (i < offset + length) {
            val word = ((buf[i].toInt() and 0xFF) shl 8) or (buf[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        while ((sum shr 16) != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv().toShort()
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Безопасный интернет FamilyPulse",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Фильтрация нежелательных сайтов на устройстве"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FamilyPulse • Защита интернета")
            .setContentText("Фильтрация нежелательного контента активна")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun stopVpn() {
        isRunning = false
        try {
            workerThread?.interrupt()
            workerThread = null
            dnsExecutor?.shutdownNow()
            dnsExecutor = null
            vpnInterface?.close()
            vpnInterface = null
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
        Log.i(TAG, "FamilyVpnService остановлен")
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}