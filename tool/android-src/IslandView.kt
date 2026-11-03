package com.codesoli.nova

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.LinearLayout
import android.widget.TextView

/** What the pill shows right now. */
class IslandModel(
    val icon: String,
    val title: String,
    val body: String = "",
    val tint: Int = 0xFF398BFF.toInt(),
    val controls: Boolean = false,
    val playing: Boolean = false,
    val mic: Boolean = false,
)

interface IslandHost {
    fun onControl(action: String)
    fun onTap()
    fun onLongPress()
    fun onDismissSwipe()
}

/**
 * The floating glass pill. Plain Android views so it can live in an overlay
 * window with no Flutter engine running.
 */
class IslandView(context: Context, private val host: IslandHost) : LinearLayout(context) {
    private val iconView = TextView(context)
    private val titleView = TextView(context)
    private val bodyView = TextView(context)
    private val prevView = control("⏮", "previous")
    private val playView = control("▶", "toggle")
    private val nextView = control("⏭", "next")
    private val micView = control("🎙", "mic")
    private val textColumn = LinearLayout(context)
    private val iconBg = GradientDrawable()
    private var hasContent = false

    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean = true
        override fun onSingleTapUp(e: MotionEvent): Boolean { host.onTap(); return true }
        override fun onLongPress(e: MotionEvent) { host.onLongPress() }
        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            if (vy < -600f) { host.onDismissSwipe(); return true }
            return false
        }
    })

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(10), dp(7), dp(12), dp(7))
        minimumHeight = dp(40)
        minimumWidth = dp(200)
        background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0xF21B2745.toInt(), 0xF20C1424.toInt())
        ).apply {
            cornerRadius = dp(40).toFloat()
            setStroke(dp(1), 0x33FFFFFF)
        }
        elevation = dp(10).toFloat()

        iconBg.shape = GradientDrawable.OVAL
        iconView.apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = iconBg
        }
        addView(iconView, LayoutParams(dp(30), dp(30)))

        val column = textColumn.apply {
            orientation = VERTICAL
            setPadding(dp(10), 0, dp(4), 0)
        }
        titleView.apply {
            textSize = 13.5f
            setTextColor(0xFFF2F6FF.toInt())
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = (resources.displayMetrics.widthPixels * 0.56f).toInt()
        }
        bodyView.apply {
            textSize = 12f
            setTextColor(0xFF9FB0CB.toInt())
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = (resources.displayMetrics.widthPixels * 0.56f).toInt()
        }
        column.addView(titleView)
        column.addView(bodyView)
        addView(column, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))

        addView(prevView, LayoutParams(dp(34), dp(34)))
        addView(playView, LayoutParams(dp(34), dp(34)))
        addView(nextView, LayoutParams(dp(34), dp(34)))
        addView(micView, LayoutParams(dp(34), dp(34)))
        contentDescription = "Nova island"
    }

    private fun control(glyph: String, action: String): TextView = TextView(context).apply {
        text = glyph
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        setOnClickListener { host.onControl(action) }
        contentDescription = action
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onTouchEvent(event: MotionEvent): Boolean = gestures.onTouchEvent(event) || super.onTouchEvent(event)

    /** Replaces the content. Returns true when it changed (caller may pop). */
    fun render(model: IslandModel) {
        iconView.text = model.icon
        iconBg.setColor((model.tint and 0x00FFFFFF) or 0x33000000)
        iconBg.setStroke(dp(1), (model.tint and 0x00FFFFFF) or 0x66000000)
        titleView.text = model.title
        bodyView.text = model.body
        bodyView.visibility = if (model.body.isBlank()) View.GONE else View.VISIBLE
        val showControls = model.controls
        prevView.visibility = if (showControls) View.VISIBLE else View.GONE
        playView.visibility = if (showControls) View.VISIBLE else View.GONE
        nextView.visibility = if (showControls) View.VISIBLE else View.GONE
        playView.text = if (model.playing) "⏸" else "▶"
        micView.visibility = if (model.mic) View.VISIBLE else View.GONE
        hasContent = true
    }

    /** Cross-fades to new content (used when the small pill rotates its details). */
    fun renderAnimated(model: IslandModel) {
        val parts = listOf<View>(iconView, textColumn)
        parts.forEach { it.animate().alpha(0f).setDuration(140).start() }
        postDelayed({
            render(model)
            parts.forEach { it.alpha = 0f; it.animate().alpha(1f).setDuration(200).start() }
        }, 150)
    }

    fun animateIn() {
        alpha = 0f
        scaleX = 0.6f
        scaleY = 0.6f
        translationY = -dp(24).toFloat()
        pivotX = width / 2f
        animate().alpha(1f).scaleX(1f).scaleY(1f).translationY(0f)
            .setDuration(320).setInterpolator(OvershootInterpolator(1.05f)).start()
    }

    fun pop() {
        pivotX = width / 2f
        scaleX = 0.94f
        scaleY = 0.94f
        animate().scaleX(1f).scaleY(1f).setDuration(220)
            .setInterpolator(OvershootInterpolator(1.4f)).start()
    }

    fun animateOut(end: () -> Unit) {
        pivotX = width / 2f
        animate().alpha(0f).scaleX(0.7f).scaleY(0.7f).translationY(-dp(16).toFloat())
            .setDuration(200).setInterpolator(AccelerateInterpolator()).withEndAction { end() }.start()
    }
}
