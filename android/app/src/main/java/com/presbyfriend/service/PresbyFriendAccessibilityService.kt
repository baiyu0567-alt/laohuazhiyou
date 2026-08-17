package com.presbyfriend.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat

import android.os.Build
import android.os.Handler
import android.os.Looper

import org.json.JSONArray
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import android.widget.Toast
import com.presbyfriend.MainActivity
import com.presbyfriend.R
import com.presbyfriend.core.capture.OcrEngine
import com.presbyfriend.core.capture.PositionedBlock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

class PresbyFriendAccessibilityService : AccessibilityService() {

    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var isProcessing = false
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        try { showOverlay() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        try { removeOverlay() } catch (_: Exception) {}
    }

    // region Overlay

    private fun showOverlay() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val d = resources.displayMetrics.density
        val size = (52 * d).toInt()
        val padding = (10 * d).toInt()

        val button = ImageView(this).apply {
            setImageResource(R.drawable.ic_magnifier)
            setColorFilter(0xFF3A7BC8.toInt())
            setBackgroundResource(R.drawable.overlay_button_bg)
            setPadding(padding, padding, padding, padding)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setOnTouchListener { _, event -> handleTouch(event) }
        }

        layoutParams = WindowManager.LayoutParams(
            size, size,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - size - 48
            y = resources.displayMetrics.heightPixels / 3
        }

        windowManager!!.addView(button, layoutParams)
        overlayView = button
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        val params = layoutParams ?: return false
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = params.x; initialY = params.y
                initialTouchX = event.rawX; initialTouchY = event.rawY
                isDragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = (event.rawX - initialTouchX).toInt()
                val dy = (event.rawY - initialTouchY).toInt()
                if (kotlin.math.abs(dx) > 10 || kotlin.math.abs(dy) > 10) isDragging = true
                if (isDragging) {
                    params.x = initialX + dx; params.y = initialY + dy
                    windowManager?.updateViewLayout(overlayView, params)
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!isDragging) onButtonTap()
                return true
            }
        }
        return false
    }

    private fun removeOverlay() {
        overlayView?.let { windowManager?.removeView(it) }
        overlayView = null
    }

    // endregion

    // region Button action

    private fun onButtonTap() {
        if (isProcessing) return
        isProcessing = true

        val store = (applicationContext as com.presbyfriend.PresbyFriendApp).settingsStore
        scope.launch {
            val canUse = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                store.canUseToday()
            }
            if (!canUse) {
                openPaywall()
                resetProcessing()
                return@launch
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                screenshotThenOcr()
            } else {
                fallbackToNodeTree()
            }
        }
    }

    private fun screenshotThenOcr() {
        val displayId = try {
            val dm = getSystemService(DISPLAY_SERVICE) as android.hardware.display.DisplayManager
            dm.getDisplay(android.view.Display.DEFAULT_DISPLAY).displayId
        } catch (_: Exception) { 0 }

        val executor = Executors.newSingleThreadExecutor()

        try {
            takeScreenshot(displayId, executor, object : TakeScreenshotCallback {
                override fun onSuccess(result: ScreenshotResult) {
                    val bitmap = try {
                        val buffer = result.hardwareBuffer
                        val wrapped = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                        buffer.close()
                        val copy = wrapped?.copy(Bitmap.Config.ARGB_8888, false)
                        wrapped?.recycle()
                        copy
                    } catch (e: Exception) {
                        result.hardwareBuffer.close()
                        fallbackToNodeTree()
                        return
                    }
                    if (bitmap == null) {
                        fallbackToNodeTree()
                        return
                    }
                    // Crop top 10% to remove status bar + toolbar noise
                    val cropped = Bitmap.createBitmap(bitmap, 0, bitmap.height / 10,
                        bitmap.width, bitmap.height - bitmap.height / 10)
                    bitmap.recycle()
                    scope.launch {
                        val allBlocks: List<PositionedBlock> = try {
                            withContext(Dispatchers.Default) { OcrEngine.recognize(cropped) }
                        } finally {
                            cropped.recycle()
                        }
                        // Exclude blocks that start in the bottom 5% (nav bars, input fields, gesture bar).
                        // Uses topYRatio so content that extends into the bottom zone from above is kept.
                        val contentBlocks = allBlocks.filter { it.topYRatio < 0.95 }
                        val display = if (contentBlocks.isNotEmpty()) contentBlocks else allBlocks
                        if (display.isNotEmpty()) {
                            openReader(display.joinToString("\n\n") { it.text })
                        } else {
                            fallbackToNodeTree()
                            return@launch
                        }
                        resetProcessing()
                    }
                }

                override fun onFailure(errorCode: Int) {
                    fallbackToNodeTree()
                }
            })
        } catch (e: Exception) {
            fallbackToNodeTree()
        }
    }

    private fun fallbackToNodeTree() {
        val text = extractFromNodeTree()
        if (text.isNotBlank()) {
            openReader(text)
        } else {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(this, R.string.no_text_found, Toast.LENGTH_SHORT).show()
            }
        }
        resetProcessing()
    }

    private fun resetProcessing() {
        Handler(Looper.getMainLooper()).postDelayed({ isProcessing = false }, 800)
    }

    // endregion

    // region Node tree extraction (fallback)

    private fun extractFromNodeTree(): String {
        val root = rootInActiveWindow ?: return ""
        if (root.packageName == packageName) {
            root.recycle()
            return ""
        }
        val screenH = resources.displayMetrics.heightPixels
        val visibleTop = screenH / 20  // skip status bar only
        val fragments = mutableListOf<Pair<Int, String>>()
        collectTextFragments(root, visibleTop, screenH, fragments)
        root.recycle()
        if (fragments.isEmpty()) return ""

        // Sort by Y position for visual reading order
        fragments.sortBy { it.first }

        // Merge fragments at similar Y positions into paragraphs.
        // Wikipedia splits sentences into tiny per-word nodes; we reconstruct them.
        val merged = mutableListOf<Pair<Int, StringBuilder>>()
        for ((y, text) in fragments) {
            if (merged.isNotEmpty() && kotlin.math.abs(y - merged.last().first) < 60) {
                // Same line or nearby: append to current paragraph
                val sb = merged.last().second
                if (sb.isNotEmpty() && !text.startsWith(".") && !text.startsWith(",") && !text.startsWith(")")) {
                    sb.append(" ")
                }
                sb.append(text)
            } else {
                merged.add(y to StringBuilder(text))
            }
        }

        val paragraphs = merged.map { it.second.toString() }
        return paragraphs.filter { it.isNotBlank() }.joinToString("\n\n")
    }

    private fun collectTextFragments(
        node: AccessibilityNodeInfo,
        visibleTop: Int,
        visibleBottom: Int,
        out: MutableList<Pair<Int, String>>
    ) {
        val rect = android.graphics.Rect()
        node.getBoundsInScreen(rect)
        val nodeCenterY = rect.centerY()
        if (nodeCenterY in visibleTop..visibleBottom) {
            val t = node.text?.toString()?.trim()
            if (!t.isNullOrBlank() && t.length > 1) {
                out.add(nodeCenterY to t)
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectTextFragments(child, visibleTop, visibleBottom, out)
            child.recycle()
        }
    }

    // endregion

    private fun openReader(text: String) {
        scope.launch {
            val store = (applicationContext as com.presbyfriend.PresbyFriendApp).settingsStore
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                store.recordUse()
            }
        }
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .setAction(Intent.ACTION_SEND)
            .putExtra(Intent.EXTRA_TEXT, text)
            .setType("text/plain")
        startActivity(intent)
    }

    private fun openPaywall() {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, R.string.daily_limit_reached, Toast.LENGTH_LONG).show()
        }
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("show_paywall", true)
        startActivity(intent)
    }
}
