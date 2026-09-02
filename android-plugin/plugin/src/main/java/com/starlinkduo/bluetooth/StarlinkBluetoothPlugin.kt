package com.starlinkduo.bluetooth

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
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

class StarlinkBluetoothPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val REQUEST_BLUETOOTH_PERMISSIONS = 4102
        private const val SERVICE_NAME = "StarlinkDuo"
        private const val MAX_MESSAGE_BYTES = 1_048_576
    }

    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val messages = ConcurrentLinkedQueue<String>()
    private val errors = ConcurrentLinkedQueue<String>()

    @Volatile private var state = "idle"
    @Volatile private var serverSocket: BluetoothServerSocket? = null
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: DataOutputStream? = null

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    private fun adapter(): BluetoothAdapter? {
        val manager = activity?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    @UsedByGodot
    fun isBluetoothAvailable(): Boolean = adapter() != null

    @UsedByGodot
    fun getState(): String = state

    @UsedByGodot
    fun requestBluetoothPermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
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
        closeSockets()
        state = "listening"
        executor.execute {
            try {
                val server = bluetooth.listenUsingRfcommWithServiceRecord(SERVICE_NAME, UUID.fromString(serviceUuid))
                serverSocket = server
                val accepted = server.accept()
                server.close()
                serverSocket = null
                attach(accepted)
            } catch (error: Exception) {
                if (state != "closed") report("host_failed", error)
            }
        }
        return true
    }

    @UsedByGodot
    fun connectToDevice(address: String, serviceUuid: String): Boolean {
        val bluetooth = adapter() ?: return fail("bluetooth_unavailable")
        if (!hasConnectPermission()) return fail("permission_required")
        closeSockets()
        state = "connecting"
        executor.execute {
            try {
                bluetooth.cancelDiscovery()
                val device = bluetooth.getRemoteDevice(address)
                val pending = device.createRfcommSocketToServiceRecord(UUID.fromString(serviceUuid))
                pending.connect()
                attach(pending)
            } catch (error: Exception) {
                report("connect_failed", error)
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
    fun closeConnection() {
        state = "closed"
        closeSockets()
    }

    private fun attach(connectedSocket: BluetoothSocket) {
        socket = connectedSocket
        output = DataOutputStream(connectedSocket.outputStream)
        state = "connected"
        try {
            val input = DataInputStream(connectedSocket.inputStream)
            while (state == "connected") {
                val size = input.readInt()
                if (size !in 1..MAX_MESSAGE_BYTES) throw IOException("invalid_message_size:$size")
                val payload = ByteArray(size)
                input.readFully(payload)
                messages.add(payload.toString(Charsets.UTF_8))
            }
        } catch (_: EOFException) {
            if (state != "closed") state = "disconnected"
        } catch (error: IOException) {
            if (state != "closed") report("read_failed", error)
        } finally {
            closeSockets()
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

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return activity?.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
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

    override fun onMainDestroy() {
        closeConnection()
        executor.shutdownNow()
        super.onMainDestroy()
    }
}

