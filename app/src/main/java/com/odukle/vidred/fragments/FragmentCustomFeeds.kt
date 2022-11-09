package com.odukle.vidred.fragments

import android.graphics.Typeface
import androidx.lifecycle.ViewModelProvider
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.imageview.ShapeableImageView
import com.google.android.material.shape.CornerFamily
import com.google.android.material.snackbar.BaseTransientBottomBar
import com.google.android.material.snackbar.Snackbar
import com.google.android.material.textfield.TextInputEditText
import com.google.common.base.CharMatcher
import com.google.gson.JsonParser
import com.odukle.vidred.MainActivity
import com.odukle.vidred.R
import com.odukle.vidred.adapters.SearchAdapter
import com.odukle.vidred.models.MultiReddit
import com.odukle.vidred.utils.*
import kotlinx.android.synthetic.main.activity_main.*
import kotlinx.android.synthetic.main.bottom_sheet_subreddits_cf.view.*
import kotlinx.android.synthetic.main.fragment_custom_feeds.*
import kotlinx.coroutines.launch

private const val TAG = "FragmentCustomFeeds"

class FragmentCustomFeeds : Fragment(), SearchAdapter.OnRemoveSubreddit {

    companion object {
        fun newInstance() = FragmentCustomFeeds()
    }

    private lateinit var viewModel: CustomFeedsViewModel
    private lateinit var activity: MainActivity
    private lateinit var sheet: BottomSheetDialog
    private var bottomSheetView: View? = null
    private var indexOfLastClickedFeed: Int = 0
    private var fragmentRestarted = false

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        activity = requireActivity() as MainActivity
        return inflater.inflate(R.layout.fragment_custom_feeds, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        viewModel = ViewModelProvider(this)[CustomFeedsViewModel::class.java]

        activity.redditLive.observe(viewLifecycleOwner) {
            if (it.authManager.currentUsername() == USER_LESS) {
                constraintLayout_feeds.hide()
                btn_sign_in.show()
                return@observe
            }
            if (isOnline(activity)) viewModel.getCustomFeeds(it)
            else showNoInternetToast(activity)
        }

        viewModel.cfJson.observe(viewLifecycleOwner) { cfJson ->
            if (cfJson.isEmpty()) return@observe

            try {
                layout_feeds_cf.removeAllViews()
                val feedArray = JsonParser.parseString(cfJson).asJsonArray
                feedArray.forEach { ele ->
                    val feed = ele.asJsonObject["data"].asJsonObject
                    val multiReddit = MultiReddit(
                        feed["name"].asString,
                        feed["display_name"].asString,
                        feed["icon_url"].asString,
                        feed["subreddits"].asJsonArray.map { it.asJsonObject["name"].asString }.toMutableList()
                    )

                    addFeedToBottomSheet(multiReddit)
                }
                progress_bar_feeds_cf.hide()
            } catch (e: Exception) {
                Log.e(TAG, "onViewCreated: ${e.stackTraceToString()}")
                shortToast(activity, "Something went wrong ${e.localizedMessage}")
            }
        }

        create_new_feed_cf.setOnClickListener {
            layout_add_new_feed_cf.apply {
                if (isVisible) hide() else show()
            }
        }

        et_new_feed_cf.filters = arrayOf(filter)
        et_new_feed_cf.setOnEditorActionListener { v, _, _ ->
            if (!isOnline(activity)) {
                showNoInternetToast(activity)
                return@setOnEditorActionListener false
            }
            if (v.text.isNullOrEmpty()) return@setOnEditorActionListener false

            layout_add_new_feed_cf.hide()
            val displayName = (v as TextInputEditText).text.toString()
            val charMatcher = CharMatcher.anyOf(displayName)
            if (charMatcher.matchesAnyOf(blockCharacterSet)) {
                shortToast(activity, "Please enter a name without special characters")
                return@setOnEditorActionListener false
            }

            shortToast(activity, "Adding new feed...")
            v.text?.clear()
            viewModel.addMulti(displayName, activity.reddit)
            false
        }

        btn_add_cf.setOnClickListener {
            et_new_feed_cf.onEditorAction(EditorInfo.IME_ACTION_DONE)
        }

        viewModel.multiReddit.observe(viewLifecycleOwner) {
            if (it != null) {
                addFeedToBottomSheet(it)
                if (!fragmentRestarted) shortToast(activity, "Added successfully 🎉")
                fragmentRestarted = false
            }
        }

        btn_sign_in.setOnClickListener {
            activity.startSignIn()
        }
    }

    private fun addFeedToBottomSheet(multiReddit: MultiReddit) {
        val iv = ShapeableImageView(activity)
        iv.shapeAppearanceModel = iv.shapeAppearanceModel
            .toBuilder()
            .setTopRightCorner(CornerFamily.ROUNDED, 10F)
            .setTopLeftCorner(CornerFamily.ROUNDED, 10F)
            .setBottomRightCorner(CornerFamily.ROUNDED, 10F)
            .setBottomLeftCorner(CornerFamily.ROUNDED, 10F)
            .build()
        val ivParams = LinearLayout.LayoutParams(30f.toDp(), 30f.toDp())
        iv.layoutParams = ivParams
        Glide.with(activity).load(multiReddit.iconUrl).into(iv)

        val tv = TextView(activity)
        tv.typeface = Typeface.DEFAULT_BOLD
        tv.textSize = 20f
        tv.text = multiReddit.displayName
        val tvParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        tvParams.setMargins(10f.toDp(), 0, 0, 0)
        tvParams.gravity = Gravity.CENTER_VERTICAL
        tv.layoutParams = tvParams

        val ll = LinearLayout(activity)
        ll.orientation = LinearLayout.HORIZONTAL
        val llParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        ll.setPadding(0, 10f.toDp(), 0, 10f.toDp())
        val outValue = TypedValue()
        activity.theme.resolveAttribute(android.R.attr.selectableItemBackground, outValue, true)
        ll.foreground = AppCompatResources.getDrawable(activity, outValue.resourceId)
        ll.layoutParams = llParams

        ll.addView(iv)
        ll.addView(tv)

        layout_feeds_cf.addView(ll)
        ll.setOnClickListener {
            indexOfLastClickedFeed = layout_feeds_cf.indexOfChild(ll)
            showBottomSheet(multiReddit)
        }
    }

    private fun showBottomSheet(multiReddit: MultiReddit) {
        sheet = BottomSheetDialog(activity)
        bottomSheetView = LayoutInflater.from(activity).inflate(R.layout.bottom_sheet_subreddits_cf, null, false)
        sheet.setContentView(bottomSheetView!!)
        sheet.show()
        bottomSheetView?.apply {
            tv_feed_name.text = multiReddit.displayName
            rv_subreddits_cf.layoutManager = LinearLayoutManager(activity)
            viewModel.loadSubreddits(multiReddit, activity.client)

            viewModel.rList.observe(viewLifecycleOwner) {
                rv_subreddits_cf.adapter = SearchAdapter(it, multiReddit)
                if (it.isEmpty()) {
                    layout_empty_feed.show()
                    btn_browse_videos.isEnabled = false
                } else {
                    layout_empty_feed.hide()
                    btn_browse_videos.isEnabled = true
                }
            }

            viewModel.showProgress.observe(viewLifecycleOwner) {
                if (it) {
                    layout_empty_feed.hide()
                    progress_bar_sheet_cf.show()
                    rv_subreddits_cf.hide()
                } else {
                    progress_bar_sheet_cf.hide()
                    rv_subreddits_cf.show()
                }
            }

            btn_add_subreddits.setOnClickListener {
                activity.bottom_navigation.selectedItemId = R.id.discover
                sheet.dismiss()
            }

            btn_browse_videos.setOnClickListener {
                activity.onOpenFragment(FragmentHome.newInstance(FOR_MULTI, multiName = multiReddit.name))
                sheet.dismiss()
            }

            btn_delete_feed.setOnClickListener {
                sheet.dismiss()
                Snackbar.make(this@FragmentCustomFeeds.requireView(), "m/${multiReddit.displayName}", Snackbar.LENGTH_SHORT)
                    .setAction("Delete") {
                        ioScope().launch {
                            shortToast(activity, "Deleting...")
                            activity.reddit.me().multi(multiReddit.name).delete()
                            shortToast(activity, "Deleted Successfully 🎉")
                            mainScope().launch {
                                fragmentRestarted = true
                                activity.restartFragment(this@FragmentCustomFeeds.id)
                            }
                        }
                    }.show()

            }
        }
    }

    override fun onResume() {
        activity.window.setLayout(ConstraintLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        super.onResume()
    }

    private fun Float.toDp(): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics
        ).toInt()
    }

    override fun onRemoveSubreddit(subredditName: String, multiReddit: MultiReddit) {
        Snackbar.make(bottomSheetView!!, "r/$subredditName", Snackbar.LENGTH_SHORT)
            .setAction("Remove") {
                ioScope().launch {
                    shortToast(activity, "Removing...")
                    try {
                        activity.reddit.me().multi(multiReddit.name).removeSubreddit(subredditName)
                    } catch (e: Exception) {
                    }
                    shortToast(activity, "Removed successfully 🎉")
                    mainScope().launch {
                        multiReddit.subreddits.remove(subredditName)
                        viewModel.loadSubreddits(multiReddit, activity.client)
                    }
                }
            }.addCallback(object : BaseTransientBottomBar.BaseCallback<Snackbar>() {
                override fun onDismissed(transientBottomBar: Snackbar?, event: Int) {
                    if (event == DISMISS_EVENT_TIMEOUT) layout_feeds_cf.getChildAt(indexOfLastClickedFeed).performClick()
                    super.onDismissed(transientBottomBar, event)
                }
            }).show()
    }

}