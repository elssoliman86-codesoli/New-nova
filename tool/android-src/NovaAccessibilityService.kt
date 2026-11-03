package com.codesoli.nova

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Lets the assistant read the text on screen, type into the focused field and
 * press buttons in other apps. It also tells the island which app is in front.
 * Password fields are never read: their text is left out of every snapshot.
 */
class NovaAccessibilityService : AccessibilityService() {
    private var lastPackage = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        IslandState.a11yConnected = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (ignoredPackage(pkg) || pkg == lastPackage) return
        lastPackage = pkg
        IslandState.foregroundPackage = pkg
        NovaIslandService.instance?.onForegroundChanged(pkg)
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        IslandState.a11yConnected = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        IslandState.a11yConnected = false
        super.onDestroy()
    }

    private fun ignoredPackage(pkg: String): Boolean {
        val p = pkg.lowercase()
        return p == "android" || p == "com.android.systemui" || p.contains("inputmethod") ||
            p.contains("keyboard") || p.contains("permissioncontroller") || p == "com.codesoli.nova.overlay"
    }

    /** What is on screen right now. */
    class Screen(val pkg: String, val text: String, val password: Boolean, val locked: Boolean)

    private fun capture(): Screen? {
        val root = rootInActiveWindow
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val locked = try { keyguard?.isKeyguardLocked == true } catch (_: Exception) { false }
        if (root == null) return if (locked) Screen("", "", false, true) else null
        val out = StringBuilder()
        var last = ""
        var password = false
        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 40 || out.length > MAX_CHARS) return
            if (!node.isVisibleToUser) return
            if (node.isPassword) {
                password = true
                out.append("[password field]\n")
                return
            }
            val text = (node.text ?: node.contentDescription)?.toString()?.trim().orEmpty()
            if (text.isNotEmpty() && text != last) {
                out.append(text).append('\n')
                last = text
            }
            for (i in 0 until node.childCount) walk(node.getChild(i), depth + 1)
        }
        walk(root, 0)
        return Screen(root.packageName?.toString().orEmpty(), out.toString().trim(), password, locked)
    }

    private fun focusedInput(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.let { return it }
        fun firstEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.isEditable && !node.isPassword) return node
            for (i in 0 until node.childCount) firstEditable(node.getChild(i))?.let { return it }
            return null
        }
        return firstEditable(root)
    }

    private fun type(text: String): Boolean {
        val node = focusedInput() ?: return false
        if (node.isPassword) return false
        var current = node.text?.toString().orEmpty()
        if (Build.VERSION.SDK_INT >= 26 && node.isShowingHintText) current = ""
        val next = if (current.isBlank()) text else current.trimEnd() + " " + text
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, next)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun clickAny(labels: List<String>): Boolean {
        val root = rootInActiveWindow ?: return false
        for (label in labels) {
            if (label.isBlank()) continue
            val nodes = root.findAccessibilityNodeInfosByText(label)
            for (node in nodes) {
                var target: AccessibilityNodeInfo? = node
                var hops = 0
                while (target != null && !target.isClickable && hops < 5) {
                    target = target.parent
                    hops++
                }
                if (target != null && target.isClickable && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    return true
                }
            }
        }
        return false
    }

    private fun scroll(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.isScrollable) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        val node = find(root) ?: return false
        return node.performAction(
            if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        )
    }

    companion object {
        private const val MAX_CHARS = 12000

        @Volatile
        var instance: NovaAccessibilityService? = null

        /** Plain text of the screen, or null when nothing is readable. */
        fun readScreen(): String? = instance?.capture()?.text?.ifEmpty { null }

        /** Screen description for the assistant: app, lock state and text. */
        fun observe(): String {
            val service = instance ?: return "Accessibility service is off, the screen cannot be read."
            val screen = service.capture() ?: return "Nothing is readable on screen."
            val head = StringBuilder()
            if (screen.pkg.isNotEmpty()) {
                head.append("App: ").append(SystemData.appLabel(service, screen.pkg)).append(" (").append(screen.pkg).append(")\n")
            }
            if (screen.locked) head.append("[The phone is locked. The user must unlock it.]\n")
            if (screen.password) head.append("[A password / PIN field is visible. Never type it. Ask the user to unlock or sign in themselves.]\n")
            val body = if (screen.text.isBlank()) "(no readable text)" else screen.text
            return head.toString() + body
        }

        /** Changes whenever the visible text or the app changes. */
        fun fingerprint(): Int {
            val screen = instance?.capture() ?: return 0
            return (screen.pkg + "|" + screen.text + "|" + screen.locked).hashCode()
        }

        fun foreground(): String = instance?.rootInActiveWindow?.packageName?.toString().orEmpty()
        fun typeText(text: String): Boolean = instance?.type(text) ?: false
        fun click(labels: List<String>): Boolean = instance?.clickAny(labels) ?: false
        fun scroll(forward: Boolean): Boolean = instance?.scroll(forward) ?: false
        fun global(action: Int): Boolean = instance?.performGlobalAction(action) ?: false
    }
}
