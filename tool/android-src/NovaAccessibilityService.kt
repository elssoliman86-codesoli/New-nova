package com.codesoli.nova

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Lets the assistant read the text on screen, type into the focused field and
 * press buttons in other apps. The user must enable it in Android settings.
 */
class NovaAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        IslandState.a11yConnected = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

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

    private fun collect(): String? {
        val root = rootInActiveWindow ?: return null
        val out = StringBuilder()
        var last = ""
        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 40 || out.length > MAX_CHARS) return
            if (!node.isVisibleToUser) return
            val text = (node.text ?: node.contentDescription)?.toString()?.trim().orEmpty()
            if (text.isNotEmpty() && text != last) {
                out.append(text).append('\n')
                last = text
            }
            for (i in 0 until node.childCount) walk(node.getChild(i), depth + 1)
        }
        walk(root, 0)
        return out.toString().trim().ifEmpty { null }
    }

    private fun focusedInput(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.let { return it }
        fun firstEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.isEditable) return node
            for (i in 0 until node.childCount) firstEditable(node.getChild(i))?.let { return it }
            return null
        }
        return firstEditable(root)
    }

    private fun type(text: String): Boolean {
        val node = focusedInput() ?: return false
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
            val nodes = root.findAccessibilityNodeInfosByText(label)
            for (node in nodes) {
                var target: AccessibilityNodeInfo? = node
                var hops = 0
                while (target != null && !target.isClickable && hops < 4) {
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

    companion object {
        private const val MAX_CHARS = 12000

        @Volatile
        var instance: NovaAccessibilityService? = null

        fun readScreen(): String? = instance?.collect()
        fun typeText(text: String): Boolean = instance?.type(text) ?: false
        fun click(labels: List<String>): Boolean = instance?.clickAny(labels) ?: false
        fun global(action: Int): Boolean = instance?.performGlobalAction(action) ?: false
    }
}
