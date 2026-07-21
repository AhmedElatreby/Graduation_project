package com.elatreby.safety

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Silent SOS trigger: while enabled, volume-down presses are consumed here
// (both ACTION_DOWN and ACTION_UP) instead of reaching the system — no
// volume change, no system volume popup — and forwarded to Dart, which
// runs the actual 3-press pattern matching (SilentSosController). Defaults
// to disabled so a channel that isn't ready yet, or any future exception
// here, fails safe to normal volume-button behavior.
class MainActivity : FlutterActivity() {
    private val silentSosChannelName = "com.elatreby.safety/silent_sos"
    private var silentSosEnabled = false
    private var silentSosChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Must run first: this is what registers every other plugin
        // (Firebase, Maps, telephony, ...) via GeneratedPluginRegistrant.
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, silentSosChannelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    silentSosEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        silentSosChannel = channel
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (silentSosEnabled && event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            // repeatCount > 0 means this is an OS-generated auto-repeat from
            // holding the key down, not a genuine distinct press — forwarding
            // those would let an ordinary "hold to lower volume" gesture
            // satisfy the 3-presses-in-1.5s pattern and arm a real alert.
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                silentSosChannel?.invokeMethod("onVolumeDownPress", null)
            }
            return true // still consume DOWN and UP: no volume change, no popup
        }
        return super.dispatchKeyEvent(event)
    }
}
