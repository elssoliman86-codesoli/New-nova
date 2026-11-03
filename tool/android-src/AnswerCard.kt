package com.codesoli.nova

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max
import kotlin.math.min

private fun Context.dpf(value: Float): Float =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)

private fun Context.spf(value: Float): Float =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics)

/**
 * Text that arrives like water drops: a droplet falls, a ripple spreads, then
 * every word drops in one after another and leaves a small ring where it lands.
 */
class DropTextView(context: Context) : View(context) {
    private class Word(val text: String, val start: Int, val rtl: Boolean)

    private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFF2F6FF.toInt()
        textSize = context.spf(17f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = context.dpf(1.4f)
    }
    private val dropPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val oval = RectF()

    private var text = ""
    private var layout: StaticLayout? = null
    private var words: List<Word> = emptyList()
    private var stagger = 90L
    private var startedAt = 0L
    private var animator: ValueAnimator? = null
    var tint = 0xFF42C8FF.toInt()

    /** Sets the text and plays the reveal. Returns how long the reveal takes. */
    fun reveal(value: String): Long {
        text = value
        layout = null
        words = emptyList()
        val count = Regex("\\S+").findAll(value).count().coerceAtLeast(1)
        stagger = min(110L, max(35L, 3600L / count))
        val total = INTRO_MS + count * stagger + WORD_MS + RING_MS
        requestLayout()
        startedAt = SystemClock.uptimeMillis()
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = total
            interpolator = LinearInterpolator()
            addUpdateListener { invalidate() }
            start()
        }
        invalidate()
        return total
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        super.onDetachedFromWindow()
    }

    private fun build(width: Int) {
        @Suppress("DEPRECATION")
        val l = StaticLayout(text, paint, width, Layout.Alignment.ALIGN_NORMAL, 1.28f, 0f, false)
        layout = l
        words = Regex("\\S+").findAll(text).map { m ->
            Word(m.value, m.range.first, l.isRtlCharAt(m.range.first))
        }.toList()
    }

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val w = MeasureSpec.getSize(widthSpec)
        val inner = max(1, w - paddingLeft - paddingRight)
        build(inner)
        val h = (layout?.height ?: 0) + paddingTop + paddingBottom
        setMeasuredDimension(w, max(h, context.dpf(24f).toInt()))
    }

    private fun easeOutBack(x: Float): Float {
        val c1 = 1.4f
        val c3 = c1 + 1f
        val t = x - 1f
        return 1f + c3 * t * t * t + c1 * t * t
    }

    override fun onDraw(canvas: Canvas) {
        val l = layout ?: return
        val t = SystemClock.uptimeMillis() - startedAt
        canvas.save()
        canvas.translate(paddingLeft.toFloat(), paddingTop.toFloat())
        val innerWidth = (width - paddingLeft - paddingRight).toFloat()

        // The first droplet and the ripple it makes.
        if (t < INTRO_MS + 450) {
            val fall = (t / 360f).coerceIn(0f, 1f)
            if (t < 380) {
                val y = -context.dpf(10f) + (context.dpf(26f) * fall * fall)
                val r = context.dpf(4.5f)
                dropPaint.color = (tint and 0x00FFFFFF) or 0xE0000000.toInt()
                oval.set(innerWidth / 2f - r, y - r * 1.5f, innerWidth / 2f + r, y + r)
                canvas.drawOval(oval, dropPaint)
            } else {
                val rp = ((t - 380) / 650f).coerceIn(0f, 1f)
                ringPaint.color = (tint and 0x00FFFFFF) or ((1f - rp) * 150).toInt().shl(24)
                val rx = innerWidth * 0.55f * rp
                val ry = rx * 0.16f
                oval.set(innerWidth / 2f - rx, context.dpf(16f) - ry, innerWidth / 2f + rx, context.dpf(16f) + ry)
                canvas.drawOval(oval, ringPaint)
            }
        }

        for ((i, w) in words.withIndex()) {
            val begin = INTRO_MS + i * stagger
            val p = ((t - begin) / WORD_MS.toFloat()).coerceIn(0f, 1f)
            if (p <= 0f) continue
            val line = l.getLineForOffset(w.start)
            val x = l.getPrimaryHorizontal(w.start)
            val baseline = l.getLineBaseline(line).toFloat()
            val eased = easeOutBack(p)
            val dy = -(1f - eased) * context.dpf(24f)
            val scale = 1f + (1f - p) * 0.24f
            paint.alpha = (min(1f, p * 2.4f) * 255).toInt()
            paint.textAlign = if (w.rtl) Paint.Align.RIGHT else Paint.Align.LEFT
            canvas.save()
            canvas.scale(scale, scale, x, baseline)
            canvas.drawText(w.text, x, baseline + dy, paint)
            canvas.restore()

            val ringP = ((t - begin - WORD_MS) / RING_MS.toFloat())
            if (ringP in 0f..1f) {
                val wordWidth = paint.measureText(w.text)
                val cx = if (w.rtl) x - wordWidth / 2f else x + wordWidth / 2f
                val cy = baseline + context.dpf(4f)
                val rx = wordWidth / 2f + context.dpf(10f) * ringP
                val ry = context.dpf(1.5f) + context.dpf(4f) * ringP
                ringPaint.color = (tint and 0x00FFFFFF) or ((1f - ringP) * 110).toInt().shl(24)
                oval.set(cx - rx, cy - ry, cx + rx, cy + ry)
                canvas.drawOval(oval, ringPaint)
            }
        }
        paint.alpha = 255
        canvas.restore()
    }

    companion object {
        private const val INTRO_MS = 520L
        private const val WORD_MS = 420L
        private const val RING_MS = 520L
    }
}

/** The card that shows the assistant's answer under the island. */
class AnswerCard(context: Context, private val onClose: () -> Unit) : LinearLayout(context) {
    private val header = TextView(context)
    private val body = DropTextView(context)

    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean = true
        override fun onSingleTapUp(e: MotionEvent): Boolean { onClose(); return true }
        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            if (vy < -500f) { onClose(); return true }
            return false
        }
    })

    init {
        orientation = VERTICAL
        val pad = context.dpf(18f).toInt()
        setPadding(pad, context.dpf(14f).toInt(), pad, context.dpf(16f).toInt())
        background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0xF5192440.toInt(), 0xF50B1322.toInt())
        ).apply {
            cornerRadius = context.dpf(28f)
            setStroke(context.dpf(1f).toInt(), 0x40FFFFFF)
        }
        elevation = context.dpf(14f)
        header.apply {
            textSize = 12f
            setTextColor(0xFF7FD6FF.toInt())
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.08f
        }
        addView(header, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(body, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = context.dpf(8f).toInt()
        })
    }

    override fun onTouchEvent(event: MotionEvent): Boolean = gestures.onTouchEvent(event) || super.onTouchEvent(event)

    /** Shows [text]; returns how long the card should stay on screen. */
    fun show(title: String, text: String): Long {
        header.text = "✦  " + title.uppercase()
        val words = Regex("\\S+").findAll(text).count()
        val reveal = body.reveal(text)
        return reveal + max(7000L, min(55_000L, words * 420L + 3500L))
    }

    fun animateIn() {
        alpha = 0f
        scaleX = 0.82f
        scaleY = 0.3f
        translationY = -context.dpf(30f)
        pivotX = width / 2f
        pivotY = 0f
        animate().alpha(1f).scaleX(1f).scaleY(1f).translationY(0f)
            .setDuration(420).setInterpolator(OvershootInterpolator(1.1f)).start()
    }

    fun animateOut(end: () -> Unit) {
        pivotX = width / 2f
        pivotY = 0f
        animate().alpha(0f).scaleX(0.85f).scaleY(0.4f).translationY(-context.dpf(20f))
            .setDuration(240).setInterpolator(AccelerateInterpolator()).withEndAction { end() }.start()
    }
}
