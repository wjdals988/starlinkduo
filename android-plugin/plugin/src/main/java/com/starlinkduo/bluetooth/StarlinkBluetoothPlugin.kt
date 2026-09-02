package com.starlinkduo.bluetooth

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Rect
import android.view.ViewGroup
import android.widget.FrameLayout
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

class StarlinkBluetoothPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val REQUEST_BLUETOOTH_PERMISSIONS = 4102
        private const val SERVICE_NAME = "StarlinkDuo"
        private const val MAX_MESSAGE_BYTES = 1_048_576
    }

    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val messages = ConcurrentLinkedQueue<String>()
    private val errors = ConcurrentLinkedQueue<String>()
    private val connectionGeneration = AtomicLong(0)
    private val accessibilityActions = ConcurrentLinkedQueue<Int>()
    @Volatile private var accessibilityOverlay: AccessibilityOverlayView? = null
    @Volatile private var accessibilityElements: List<VirtualAccessibilityNode> = emptyList()
    @Volatile private var accessibilitySourceWidth = 1280
    @Volatile private var accessibilitySourceHeight = 720

    @Volatile private var state = "idle"
    @Volatile private var serverSocket: BluetoothServerSocket? = null
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: DataOutputStream? = null

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    override fun onGodotSetupCompleted() {
        super.onGodotSetupCompleted()
        val host = activity ?: return
        host.runOnUiThread {
            val root = host.findViewById<ViewGroup>(android.R.id.content) ?: return@runOnUiThread
            val overlay = AccessibilityOverlayView(host) { id -> accessibilityActions.add(id) }
            root.addView(overlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            accessibilityOverlay = overlay
            overlay.updateNodes(accessibilityElements, accessibilitySourceWidth, accessibilitySourceHeight)
        }
    }

    @UsedByGodot
    fun setAccessibilityElementsJson(payload: String) {
        try {
            val root = JSONObject(payload)
            val width = root.optInt("width", 1280)
            val height = root.optInt("height", 720)
            val source = root.optJSONArray("elements") ?: JSONArray()
            val elements = buildList {
                for (index in 0 until source.length()) {
                    val item = source.getJSONObject(index)
                    add(
                        VirtualAccessibilityNode(
                            id = item.getInt("id"),
                            name = item.optString("name"),
                            description = item.optString("description"),
                            sourceRect = Rect(item.getInt("left"), item.getInt("top"), item.getInt("right"), item.getInt("bottom")),
                            enabled = item.optBoolean("enabled", true),
                            role = item.optString("role", "button"),
                        )
                    )
                }
            }
            accessibilityElements = elements
            accessibilitySourceWidth = width
            accessibilitySourceHeight = height
            runOnUiThread { accessibilityOverlay?.updateNodes(elements, width, height) }
        } catch (error: Exception) {
            errors.add("accessibility_payload_invalid:${error.message ?: error.javaClass.simpleName}")
        }
    }

    @UsedByGodot
    fun pollAccessibilityAction(): Int = accessibilityActions.poll() ?: -1

    @UsedByGodot
    fun getSystemFontScale(): Float = activity?.resources?.configuration?.fontScale ?: 1.0f

    private fun adapter(): BluetoothAdapter? {
        val manager = activity?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    @UsedByGodot
    fun isBluetoothAvailable(): Boolean = adapter() != null

    @UsedByGodot
    fun isBluetoothEnabled(): Boolean = adapter()?.isEnabled == true

    @UsedByGodot
    fun hasBluetoothPermissions(): Boolean = hasConnectPermission() && hasScanPermission()

    @UsedByGodot
    fun getBondedDevicesJson(): String {
        val bluetooth = adapter() ?: return "[]"
        if (!hasConnectPermission()) return "[]"
        return try {
            val result = JSONArray()
            bluetooth.bondedDevices
                .sortedWith(compareBy({ it.name ?: "" }, { it.address }))
                .forEach { device ->
                    result.put(JSONObject().put("name", device.name ?: "이름 없는 기기").put("address", device.address))
                }
            result.toString()
        } catch (error: SecurityException) {
            report("bonded_devices_failed", error)
            "[]"
        }
    }

    @UsedByGodot
    fun getState(): String = state

    @UsedByGodot
    fun requestBluetoothPermissions() {
        val host = activity ?: return
        val permissions = arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
        ).filter { host.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (permissions.isNotEmpty()) {
            host.requestPermissions(permissions.toTypedArray(), REQUEST_BLUETOOTH_PERMISSIONS)
        }
    }

    @UsedByGodot
    fun startHost(serviceUuid: String): Boolean {
        val bluetooth = adapter() ?: return fail("bluetooth_unavailable")
        if (!hasConnectPermission()) return fail("permission_required")
        val generation = beginOperation("listening")
        executor.execute {
            try {
                val server = bluetooth.listenUsingRfcommWithServiceRecord(SERVICE_NAME, UUID.fromString(serviceUuid))
                if (!registerServerIfCurrent(server, generation)) {
                    server.close()
                    return@execute
                }
                val accepted = server.accept()
                server.close()
                clearServerIfCurrent(server, generation)
                attach(accepted, generation)
            } catch (error: SecurityException) {
                if (isCurrent(generation)) reportCurrent("permission_revoked", error, generation)
            } catch (error: Exception) {
                if (isCurrent(generation) && state != "closed") reportCurrent("host_failed", error, generation)
            }
        }
        return true
    }

    @UsedByGodot
    fun connectToDevice(address: String, serviceUuid: String): Boolean {
        val bluetooth = adapter() ?: return fail("bluetooth_unavailable")
        if (!hasConnectPermission()) return fail("permission_required")
        val generation = beginOperation("connecting")
        executor.execute {
            try {
                bluetooth.cancelDiscovery()
                val device = bluetooth.getRemoteDevice(address)
                val pending = device.createRfcommSocketToServiceRecord(UUID.fromString(serviceUuid))
                if (!registerSocketIfCurrent(pending, generation)) {
                    pending.close()
                    return@execute
                }
                pending.connect()
                attach(pending, generation)
            } catch (error: SecurityException) {
                if (isCurrent(generation)) reportCurrent("permission_revoked", error, generation)
            } catch (error: Exception) {
                if (isCurrent(generation)) reportCurrent("connect_failed", error, generation)
            }
        }
        return true
    }

    @UsedByGodot
    @Synchronized
    fun sendMessage(message: String): Boolean {
        val payload = message.toByteArray(Charsets.UTF_8)
        if (payload.size > MAX_MESSAGE_BYTES) return fail("message_too_large")
        val stream = output ?: return fail("not_connected")
        return try {
            stream.writeInt(payload.size)
            stream.write(payload)
            stream.flush()
            true
        } catch (error: IOException) {
            report("send_failed", error)
            false
        }
    }

    @UsedByGodot
    fun pollMessage(): String = messages.poll() ?: ""

    @UsedByGodot
    fun pollError(): String = errors.poll() ?: ""

    @UsedByGodot
    @Synchronized
    fun closeConnection() {
        connectionGeneration.incrementAndGet()
        state = "closed"
        closeSockets()
    }

    private fun attach(connectedSocket: BluetoothSocket, generation: Long) {
        val connectedOutput = DataOutputStream(connectedSocket.outputStream)
        if (!activateSocketIfCurrent(connectedSocket, connectedOutput, generation)) {
            try { connectedSocket.close() } catch (_: IOException) { }
            return
        }
        try {
            val input = DataInputStream(connectedSocket.inputStream)
            while (isCurrent(generation) && state == "connected") {
                val size = input.readInt()
                if (size !in 1..MAX_MESSAGE_BYTES) throw IOException("invalid_message_size:$size")
                val payload = ByteArray(size)
                input.readFully(payload)
                if (isCurrent(generation)) messages.add(payload.toString(Charsets.UTF_8))
            }
        } catch (_: EOFException) {
            if (isCurrent(generation) && state != "closed") state = "disconnected"
        } catch (error: IOException) {
            if (isCurrent(generation) && state != "closed") reportCurrent("read_failed", error, generation)
        } finally {
            closeSocketsIfCurrent(generation)
        }
    }

    @Synchronized
    private fun closeSockets() {
        output = null
        try { socket?.close() } catch (_: IOException) { }
        try { serverSocket?.close() } catch (_: IOException) { }
        socket = null
        serverSocket = null
    }

    @Synchronized
    private fun closeSocketsIfCurrent(generation: Long) {
        if (isCurrent(generation)) closeSockets()
    }

    @Synchronized
    private fun beginOperation(nextState: String): Long {
        val generation = connectionGeneration.incrementAndGet()
        closeSockets()
        messages.clear()
        errors.clear()
        state = nextState
        return generation
    }

    @Synchronized
    private fun registerServerIfCurrent(server: BluetoothServerSocket, generation: Long): Boolean {
        if (!isCurrent(generation)) return false
        serverSocket = server
        return true
    }

    @Synchronized
    private fun clearServerIfCurrent(server: BluetoothServerSocket, generation: Long) {
        if (isCurrent(generation) && serverSocket === server) serverSocket = null
    }

    @Synchronized
    private fun registerSocketIfCurrent(pending: BluetoothSocket, generation: Long): Boolean {
        if (!isCurrent(generation)) return false
        socket = pending
        return true
    }

    @Synchronized
    private fun activateSocketIfCurrent(connected: BluetoothSocket, stream: DataOutputStream, generation: Long): Boolean {
        if (!isCurrent(generation) || socket != null && socket !== connected) return false
        socket = connected
        output = stream
        state = "connected"
        return true
    }

    private fun isCurrent(generation: Long): Boolean = connectionGeneration.get() == generation

    private fun hasConnectPermission(): Boolean {
        return activity?.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasScanPermission(): Boolean {
        return activity?.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
    }

    private fun fail(code: String): Boolean {
        errors.add(code)
        return false
    }

    private fun report(code: String, error: Exception) {
        state = "error"
        errors.add("$code:${error.message ?: error.javaClass.simpleName}")
        closeSockets()
    }

    private fun reportCurrent(code: String, error: Exception, generation: Long) {
        if (!isCurrent(generation)) return
        report(code, error)
    }

    override fun onMainDestroy() {
        val overlay = accessibilityOverlay
        activity?.runOnUiThread { (overlay?.parent as? ViewGroup)?.removeView(overlay) }
        accessibilityOverlay = null
        accessibilityElements = emptyList()
        accessibilityActions.clear()
        closeConnection()
        executor.shutdownNow()
        super.onMainDestroy()
    }
}
