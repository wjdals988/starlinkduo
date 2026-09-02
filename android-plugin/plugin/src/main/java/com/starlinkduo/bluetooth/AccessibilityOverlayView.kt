package com.starlinkduo.bluetooth

import android.content.Context
import android.graphics.Rect
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import kotlin.math.min

internal data class VirtualAccessibilityNode(
    val id: Int,
    val name: String,
    val description: String,
    val sourceRect: Rect,
    val enabled: Boolean,
    val role: String,
)

internal class AccessibilityOverlayView(
    context: Context,
    private val onActivate: (Int) -> Unit,
) : View(context) {
    private val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    private val provider = VirtualNodeProvider()
    private var nodes: List<VirtualAccessibilityNode> = emptyList()
    private var sourceWidth = 1280
    private var sourceHeight = 720
    private var hoveredId = INVALID_ID
    private var accessibilityFocusedId = INVALID_ID
    private val parentLayoutListener = OnLayoutChangeListener { parentView, _, _, _, _, _, _, _, _ ->
        fitToParent(parentView)
    }

    init {
		layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = false
        isClickable = false
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), MeasureSpec.getSize(heightMeasureSpec))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
		(parent as? View)?.addOnLayoutChangeListener(parentLayoutListener)
		post {
			(parent as? View)?.let(::fitToParent)
			bringToFront()
		}
		postDelayed({ bringToFront() }, 500)
    }

	override fun onDetachedFromWindow() {
		(parent as? View)?.removeOnLayoutChangeListener(parentLayoutListener)
		super.onDetachedFromWindow()
	}

	private fun fitToParent(parentView: View) {
		if (parentView.width <= 0 || parentView.height <= 0) return
		layoutParams = FrameLayout.LayoutParams(parentView.width, parentView.height)
		measure(
			MeasureSpec.makeMeasureSpec(parentView.width, MeasureSpec.EXACTLY),
			MeasureSpec.makeMeasureSpec(parentView.height, MeasureSpec.EXACTLY),
		)
		layout(0, 0, parentView.width, parentView.height)
	}

    fun updateNodes(nextNodes: List<VirtualAccessibilityNode>, width: Int, height: Int) {
        nodes = nextNodes
		if (nodes.none { it.id == accessibilityFocusedId }) accessibilityFocusedId = INVALID_ID
		contentDescription = "스타링크 듀오 접근성 조작 영역, ${nodes.size}개 항목"
        sourceWidth = width.coerceAtLeast(1)
        sourceHeight = height.coerceAtLeast(1)
        invalidate()
        sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
    }

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider

    override fun onTouchEvent(event: MotionEvent): Boolean = false

    override fun dispatchHoverEvent(event: MotionEvent): Boolean {
        if (!manager.isEnabled || !manager.isTouchExplorationEnabled) return false
        when (event.action) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> {
                val nextId = hitTest(event.x.toInt(), event.y.toInt())
                if (nextId != hoveredId) {
                    if (hoveredId != INVALID_ID) sendVirtualEvent(hoveredId, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT)
                    hoveredId = nextId
                    if (hoveredId != INVALID_ID) sendVirtualEvent(hoveredId, AccessibilityEvent.TYPE_VIEW_HOVER_ENTER)
                }
                return nextId != INVALID_ID
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                if (hoveredId != INVALID_ID) sendVirtualEvent(hoveredId, AccessibilityEvent.TYPE_VIEW_HOVER_EXIT)
                hoveredId = INVALID_ID
                return true
            }
        }
        return false
    }

    private fun hitTest(x: Int, y: Int): Int = nodes.lastOrNull { mappedRect(it.sourceRect).contains(x, y) }?.id ?: INVALID_ID

    private fun mappedRect(source: Rect): Rect {
        val scale = min(width.toFloat() / sourceWidth, height.toFloat() / sourceHeight)
        val offsetX = (width - sourceWidth * scale) * 0.5f
        val offsetY = (height - sourceHeight * scale) * 0.5f
        return Rect(
            (offsetX + source.left * scale).toInt(),
            (offsetY + source.top * scale).toInt(),
            (offsetX + source.right * scale).toInt(),
            (offsetY + source.bottom * scale).toInt(),
        )
    }

    private fun sendVirtualEvent(id: Int, type: Int) {
        if (!manager.isEnabled) return
        val node = nodes.firstOrNull { it.id == id } ?: return
        val event = AccessibilityEvent.obtain(type)
        event.packageName = context.packageName
        event.className = nodeClassName(node)
        event.contentDescription = spokenText(node)
        event.isEnabled = node.enabled
        event.setSource(this, id)
        parent?.requestSendAccessibilityEvent(this, event)
    }

    private fun spokenText(node: VirtualAccessibilityNode): String =
        listOf(node.name, node.description).filter { it.isNotBlank() }.joinToString(". ")

    private fun nodeClassName(node: VirtualAccessibilityNode): String =
        if (node.role == "text") android.widget.TextView::class.java.name else android.widget.Button::class.java.name

    private inner class VirtualNodeProvider : AccessibilityNodeProvider() {
        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? {
            if (virtualViewId == HOST_ID) {
                return AccessibilityNodeInfo.obtain(this@AccessibilityOverlayView).apply {
                    packageName = context.packageName
                    className = android.view.ViewGroup::class.java.name
					contentDescription = this@AccessibilityOverlayView.contentDescription
					isEnabled = true
					isVisibleToUser = true
					val local = Rect(0, 0, width, height)
					setBoundsInParent(local)
					val location = IntArray(2)
					getLocationOnScreen(location)
					setBoundsInScreen(Rect(local).apply { offset(location[0], location[1]) })
                    nodes.forEach { addChild(this@AccessibilityOverlayView, it.id) }
                }
            }
            val node = nodes.firstOrNull { it.id == virtualViewId } ?: return null
            return AccessibilityNodeInfo.obtain().apply {
                packageName = context.packageName
                className = nodeClassName(node)
                setSource(this@AccessibilityOverlayView, node.id)
                setParent(this@AccessibilityOverlayView)
                contentDescription = spokenText(node)
                isEnabled = node.enabled
                isClickable = node.enabled && node.role == "button"
                isFocusable = true
				isAccessibilityFocused = accessibilityFocusedId == node.id
                isVisibleToUser = this@AccessibilityOverlayView.visibility == VISIBLE
                val local = mappedRect(node.sourceRect)
                setBoundsInParent(local)
                val location = IntArray(2)
                getLocationOnScreen(location)
                setBoundsInScreen(Rect(local).apply { offset(location[0], location[1]) })
                addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_ACCESSIBILITY_FOCUS)
                addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLEAR_ACCESSIBILITY_FOCUS)
                if (node.enabled && node.role == "button") addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            }
        }

        override fun performAction(virtualViewId: Int, action: Int, arguments: Bundle?): Boolean {
            val node = nodes.firstOrNull { it.id == virtualViewId } ?: return false
            return when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> {
                    if (!node.enabled || node.role != "button") return false
                    onActivate(node.id)
                    sendVirtualEvent(node.id, AccessibilityEvent.TYPE_VIEW_CLICKED)
                    true
                }
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> {
					if (accessibilityFocusedId != INVALID_ID && accessibilityFocusedId != node.id) {
						sendVirtualEvent(accessibilityFocusedId, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED)
					}
					accessibilityFocusedId = node.id
                    sendVirtualEvent(node.id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED)
					invalidate()
                    true
                }
                AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> {
					if (accessibilityFocusedId != node.id) return false
					accessibilityFocusedId = INVALID_ID
                    sendVirtualEvent(node.id, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED)
					invalidate()
                    true
                }
                else -> false
            }
        }
    }

    companion object {
        private const val HOST_ID = View.NO_ID
        private const val INVALID_ID = Int.MIN_VALUE
    }
}
