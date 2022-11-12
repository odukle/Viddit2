package com.odukle.vidred.fragments

import android.annotation.SuppressLint
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
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.chip.Chip
import com.google.android.material.imageview.ShapeableImageView
import com.google.android.material.shape.CornerFamily
import com.google.android.material.textfield.TextInputEditText
import com.google.common.base.CharMatcher
import com.google.gson.JsonParser
import com.odukle.vidred.ActivityViewModel
import com.odukle.vidred.MainActivity
import com.odukle.vidred.R
import com.odukle.vidred.adapters.SubredditAdapter
import com.odukle.vidred.models.MultiReddit
import com.odukle.vidred.utils.*
import kotlinx.android.synthetic.main.bottomsheet_cf.view.*
import kotlinx.android.synthetic.main.fragment_subreddit.*
import kotlinx.coroutines.launch
import net.dean.jraw.models.TimePeriod
import net.dean.jraw.references.OtherUserReference
import kotlin.properties.Delegates

private const val TAG = "SubredditFragment"

class SubredditFragment : Fragment(), SubredditAdapter.OnLoadMoreDataSR {

    companion object {
        fun newInstance(subreddit: String, isUser: Boolean = false) = SubredditFragment().apply {
            arguments = Bundle().apply {
                putString(SUBREDDIT_NAME, subreddit)
                putBoolean(IS_USER, isUser)
            }
        }
    }

    private lateinit var viewModel: SubredditViewModel
    private lateinit var activityViewModel: ActivityViewModel
    private lateinit var subredditName: String
    private lateinit var activity: MainActivity
    var isUser by Delegates.notNull<Boolean>()
    private var bottomSheetDialog: BottomSheetDialog? = null
    private var bottomSheetView: View? = null
    private lateinit var subredditToAdd: String

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val view = inflater.inflate(R.layout.fragment_subreddit, container, false)
        activity = requireActivity() as MainActivity
        viewModel = ViewModelProvider(this)[SubredditViewModel::class.java]
        activityViewModel = ViewModelProvider(activity)[ActivityViewModel::class.java]
        subredditName = requireArguments().getString(SUBREDDIT_NAME)!!
        isUser = requireArguments().getBoolean(IS_USER)
        return view
    }

    @SuppressLint("SetTextI18n", "NotifyDataSetChanged")
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        rv_subreddit.layoutManager = CustomGLM(activity, 3)
        activityViewModel.vList.clear()
        if (subredditName != activityViewModel.prevSubredditName) {
            activityViewModel.prevSubredditName = subredditName
            activityViewModel.srPosition = 0
            activityViewModel.vList.addAll(viewModel.adapter.vList)
            rv_subreddit.adapter = viewModel.adapter
        } else {
            viewModel.adapter.vList.addAll(activityViewModel.vList)
            viewModel.pagesLive.postValue(activityViewModel.srPages)
            rv_subreddit.adapter = viewModel.adapter
            rv_subreddit.scrollToPosition(activityViewModel.srPosition)
        }

        showShimmer()
        ioScope().launch {
            viewModel.getSubredditRef(activity.reddit, subredditName, isUser)
        }

        viewModel.subredditRef.observe(viewLifecycleOwner) { srf ->
            if (viewModel.adapter.vList.isEmpty()) {
                srf?.let { viewModel.getSRPages(it, isUser = isUser) }
            }

            if (isUser && srf != null) {
                srf as OtherUserReference
                hideShimmer()
                chip_rising.hide()
                chip_add_to_cf.hide()
                tv_members.hide()
                val params = scroll_view_chips.layoutParams as ConstraintLayout.LayoutParams
                params.topToBottom = iv_icon_sr.id
                scroll_view_chips.layoutParams = params
                ioScope().launch {
                    val icon = getUserIcon(srf.username, activity.client)
                    mainScope().launch {
                        Glide.with(view)
                            .load(icon)
                            .placeholder(R.drawable.ic_reddit)
                            .into(iv_icon_sr)

                        tv_subreddit_name.text = srf.username
                    }
                }
            }
        }

        viewModel.pagesLive.observe(viewLifecycleOwner) {
            if (it != null && activityViewModel.srPages != null) {
                if (activityViewModel.srPages!!.sorting == it.sorting
                    && activityViewModel.srPages!!.baseUrl == it.baseUrl) {
                    Log.d(TAG, "onViewCreated: returning")
                    return@observe
                }
            }
            activityViewModel.srPages = it
            activityViewModel.srPosition = 0
            viewModel.adapter.pages = it
            viewModel.adapter.vList.clear()
            viewModel.adapter.notifyDataSetChanged()
            progress_bar_sr.show()
            if (it != null) {
                ioScope().launch {
                    viewModel.job?.cancel()
                    viewModel.loadMoreDataSR(it)

                    mainScope().launch {
                        progress_bar_sr.hide()
                    }
                }
            }
        }

        ioScope().launch {
            viewModel.getSubreddit(subredditName, activity.client)
        }

        viewModel.subreddit.observe(viewLifecycleOwner) { subReddit ->
            if (!isUser) {
                hideShimmer()
                Glide.with(view)
                    .load(subReddit.icon)
                    .placeholder(R.drawable.ic_reddit)
                    .into(iv_icon_sr)

                tv_subreddit_name.text = if (!isUser) subReddit.title else subReddit.titlePrefixed
                tv_members.text = subReddit.subscribers + " members"
                tv_desc.text = subReddit.desc
                tv_desc_full.text = subReddit.desc
            }
        }

        viewModel.isRefreshing.observe(viewLifecycleOwner) {
            if (it) progress_bar_sr.show()
            else progress_bar_sr.hide()
        }

        viewModel.videosExhausted.observe(viewLifecycleOwner) {
            if (it) {
                shortToast(activity, "All videos loaded for $subredditName:${viewModel.pagesLive.value?.sorting}")
            }
        }

        viewModel.dataLoaded.observe(viewLifecycleOwner) {
            if (it) {
                runAfter(100) {
                    try {
                        rv_subreddit.smoothScrollToPosition(activityViewModel.srPosition)
                    } catch (e: Exception) {
                    }
                }
            }
        }

        chip_group_sr.setOnCheckedStateChangeListener { group, checkedIds ->
            val chip = group.findViewById<Chip>(group.checkedChipId)
            if (chip != null) {
                val order = chip.tag as String
                if (chip.id != chip_top.id) {
                    viewModel.subredditRef.value?.let { viewModel.getSRPages(it, getSubredditSort(order), isUser) }
                    chip_group_time.hide()
                    chip_group_time.clearCheck()
                    chip_top.text = "Top"
                } else {
                    if (chip_group_time.checkedChipId == View.NO_ID) chip_top_today.isChecked = true
                    scroll_view_time.apply {
                        if (isVisible) hide() else show()
                    }
                }
            }
        }

        chip_group_time.setOnCheckedStateChangeListener { group, _ ->
            val chip = group.findViewById<Chip>(group.checkedChipId)
            if (chip != null) {
                chip.bounce()
                val time = (chip.tag ?: "day") as String
                chip_top.text = chip.text
                val timePeriod = when (time) {
                    "hour" -> TimePeriod.HOUR
                    "day" -> TimePeriod.DAY
                    "week" -> TimePeriod.WEEK
                    "month" -> TimePeriod.MONTH
                    "year" -> TimePeriod.YEAR
                    "all" -> TimePeriod.ALL
                    else -> TimePeriod.DAY
                }

                viewModel.subredditRef.value?.let { viewModel.getSRPages(it, getSubredditSort(TOP), isUser, timePeriod) }
            }
        }

        chip_add_to_cf.setOnClickListener {
            showCustomFeeds(subredditName)
        }

        viewModel.cfJson.observe(viewLifecycleOwner) { cfJson ->
            if (cfJson.isEmpty()) return@observe

            bottomSheetView?.apply {
                try {
                    layout_cf.removeAllViews()
                    val feedArray = JsonParser.parseString(cfJson).asJsonArray
                    feedArray.forEach { ele ->
                        val feed = ele.asJsonObject["data"].asJsonObject
                        val multiReddit = MultiReddit(
                            feed["name"].asString,
                            feed["display_name"].asString,
                            feed["icon_url"].asString,
                            feed["subreddits"].asJsonArray.map { it.asJsonObject["name"].asString }.toMutableList()
                        )

                        addFeedToBottomSheet(multiReddit, subredditToAdd)
                    }
                    progress_bar_cf.hide()
                } catch (e: Exception) {
                }
            }
        }

        viewModel.subredditAdded.observe(viewLifecycleOwner) {
            if (it) {
                Log.d(TAG, "addFeedToBottomSheet: this was not supposed to happen")
                bottomSheetDialog?.dismiss()
                shortToast(activity, "Added successfully 🎉")
            }
        }
    }

    private fun showCustomFeeds(subredditName: String) {
        subredditToAdd = subredditName
        showBottomSheetDialog()
        bottomSheetView?.apply {
            progress_bar_cf.show()
            val reddit = activity.reddit
            if (reddit.authManager.currentUsername() == USER_LESS) return@apply
            ioScope().launch {
                if (isOnline(activity)) viewModel.getCustomFeeds(reddit)
                else showNoInternetToast(activity)
            }

            layout_sign_in.setOnClickListener {
                bottomSheetDialog?.dismiss()
                activity.startSignIn()
            }

            create_new_feed.setOnClickListener {
                layout_add_new_feed.apply {
                    if (isVisible) hide() else show()
                }
            }

            et_new_feed.filters = arrayOf(filter)
            et_new_feed.setOnEditorActionListener { v, _, _ ->
                if (!isOnline(activity)) {
                    showNoInternetToast(activity)
                    return@setOnEditorActionListener false
                }
                if (v.text.isNullOrEmpty()) return@setOnEditorActionListener false

                layout_add_new_feed.hide()
                val displayName = (v as TextInputEditText).text.toString()
                val charMatcher = CharMatcher.anyOf(displayName)
                if (charMatcher.matchesAnyOf(blockCharacterSet)) {
                    shortToast(activity, "Please enter a name without special characters")
                    return@setOnEditorActionListener false
                }

                shortToast(activity, "Adding new feed...")
                v.text?.clear()
                viewModel.addMulti(displayName, reddit)
                false
            }

            btn_add.setOnClickListener {
                et_new_feed.onEditorAction(EditorInfo.IME_ACTION_DONE)
            }

            viewModel.multiReddit.observe(viewLifecycleOwner) {
                if (it != null) {
                    addFeedToBottomSheet(it, subredditName)
                }
            }
        }
    }

    private fun showBottomSheetDialog() {
        bottomSheetDialog = BottomSheetDialog(activity)
        bottomSheetView = LayoutInflater.from(activity).inflate(R.layout.bottomsheet_cf, null, false)
        bottomSheetDialog?.setContentView(bottomSheetView!!)
        bottomSheetDialog?.show()

        bottomSheetView?.apply {
            if (activity.reddit.authManager.currentUsername() == USER_LESS) {
                layout_main_content.hide()
                layout_sign_in.show()
            } else {
                layout_main_content.show()
                layout_sign_in.hide()
            }
        }
    }

    private fun addFeedToBottomSheet(multiReddit: MultiReddit, subredditName: String) {
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

        ll.setOnClickListener {
            if (isOnline(activity)) {
                shortToast(activity, "Adding..")
                viewModel.addSubRedditToCf(activity.reddit, multiReddit.name, subredditName)
            } else showNoInternetToast(activity)

        }

        bottomSheetView?.apply {
            layout_cf.addView(ll)
        }
    }

    private fun showShimmer() {
        shimmer_sr.show()
        tv_desc.hide()
        tv_desc_full.hide()
        tv_members.hide()
        tv_subreddit_name.hide()
    }

    private fun hideShimmer() {
        shimmer_sr.hide()
        tv_desc.show()
        tv_members.show()
        tv_subreddit_name.show()
    }

    override fun onDestroyView() {
        activityViewModel.vList.clear()
        activityViewModel.vList.addAll(viewModel.adapter.vList)
        activityViewModel.srPosition = (rv_subreddit.layoutManager as CustomGLM).findFirstCompletelyVisibleItemPosition()
        super.onDestroyView()
    }

    override fun onLoadMoreDataSR() {
        val runnable = kotlinx.coroutines.Runnable {
            if (viewModel.videosExhausted.value == false) {
                viewModel.pagesLive.value?.let { viewModel.loadMoreDataSR(it) }
            }
        }
        viewModel.job?.let { job ->
            if (!job.isActive) {
                runnable.run()
            }
        } ?: runnable.run()
    }

    private fun Float.toDp(): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics
        ).toInt()
    }
}