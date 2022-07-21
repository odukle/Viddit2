package com.odukle.viddit.fragments

import android.animation.LayoutTransition
import android.annotation.SuppressLint
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.util.Linkify
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.imageview.ShapeableImageView
import com.google.gson.JsonArray
import com.odukle.viddit.ActivityViewModel
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.models.AboutPost
import com.odukle.viddit.utils.*
import com.squareup.moshi.Types
import kotlinx.android.synthetic.main.bottom_sheet_comments.view.*
import kotlinx.android.synthetic.main.fragment_home.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.dean.jraw.JrawUtils
import net.dean.jraw.models.Submission
import java.lang.reflect.Type
import kotlin.properties.Delegates

private const val TAG = "FragmentHome"

class FragmentHome : Fragment(), VideoAdapter.OnCallback, VideoAdapter.OnFragmentCallback {

    companion object {
        fun newInstance(
            calledFor: Int = 1,
            jsonList: String = "",
            adapterPosition: Int = 0,
            subredditName: String = "",
            sorting: String = HOT,
            multiName: String = "",
        ) = FragmentHome().apply {
            arguments = Bundle().apply {
                putInt(CALLED_FOR, calledFor)
                putString(JSON_LIST, jsonList)
                putInt(ADAPTER_POSITION, adapterPosition)
                putString(SUBREDDIT_NAME, subredditName)
                putString(SORTING, sorting)
                putString(MULTI_NAME, multiName)
            }
        }
    }

    private lateinit var viewModel: HomeViewModel
    private lateinit var activityViewModel: ActivityViewModel
    private lateinit var activity: MainActivity
    private var calledFor by Delegates.notNull<Int>()
    private lateinit var jsonList: String
    private var adapterPosition by Delegates.notNull<Int>()
    private lateinit var subredditName: String
    private lateinit var sorting: String
    private lateinit var multiName: String
    private var job: Job? = null
    private lateinit var commentsView: View

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        calledFor = requireArguments().getInt(CALLED_FOR)
        jsonList = requireArguments().getString(JSON_LIST, "")
        adapterPosition = requireArguments().getInt(ADAPTER_POSITION)
        subredditName = requireArguments().getString(SUBREDDIT_NAME, "")
        sorting = requireArguments().getString(SORTING, HOT)
        multiName = requireArguments().getString(MULTI_NAME, "")
        return inflater.inflate(R.layout.fragment_home, container, false)
    }

    @SuppressLint("SetTextI18n")
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        activity = requireActivity() as MainActivity
        viewModel = ViewModelProvider(activity)[HomeViewModel::class.java]
        activityViewModel = ViewModelProvider(activity)[ActivityViewModel::class.java]

        layout_refresh.setProgressViewOffset(false, 60F.toDp(), 100F.toDp())
        when (calledFor) {
            FOR_MAIN -> {
                chip_sr.hide()
                chip_multi.hide()
                if (viewModel.adapter.content == POPULAR) {
                    chip_popular.isChecked = true
                    chip_popular.setChipBackgroundColorResource(R.color.orange)
                    chip_front_page.setChipBackgroundColorResource(R.color.chipBg)
                }
                if (viewModel.tempList.isNotEmpty()) {
                    viewModel.adapter.vList.clear()
                    viewModel.adapter.vList.addAll(viewModel.tempList)
                    viewModel.adapterPosition = viewModel.tempPosition
                    viewModel.tempList.clear()
                    viewModel.pages = viewModel.tempPages
                }

                activity.redditLive.observe(viewLifecycleOwner) {
                    if (viewModel.adapter.vList.isEmpty()) {
                        ioScope().launch {
                            viewModel.pages = viewModel.getPages(FOR_MAIN, it)
                            viewModel.loadMoreData(viewModel.pages!!)
                        }
                    }

                    if (it.authManager.currentUsername() == USER_LESS) chip_group_choose_feed.hide()
                    else chip_group_choose_feed.show()
                }
            }

            FOR_SUBREDDIT -> {
                chip_sr.show()
                chip_sr.text = "r/$subredditName"
                chip_multi.hide()
                chip_group_choose_feed.hide()
                viewModel.pages = activityViewModel.srPages
                val typeList: Type = Types.newParameterizedType(
                    MutableList::class.java,
                    Submission::class.java
                )

                val jsonListAdapter = JrawUtils.moshi.adapter<MutableList<Submission>>(typeList).serializeNulls()
                val list = jsonListAdapter.fromJson(jsonList)

                if (list != null) {
                    val submission = list[adapterPosition]
                    val vList = placeAds(list.toMutableList())
                    adapterPosition = vList.indexOf(submission)
                    viewModel.adapter.vList = vList
                }
                val lastSubmission = viewModel.adapter.vList.last()
                ioScope().launch {
                    viewModel.pages?.forEach {
                        while (!it.toList().contains(lastSubmission)) {
                            viewModel.pages!!.next()
                        }
                    }
                }
                viewModel.adapterPosition = adapterPosition
            }

            FOR_MULTI -> {
                chip_multi.show()
                chip_multi.text = multiName
                chip_group_choose_feed.hide()
                chip_sr.hide()
                viewModel.adapter.vList.clear()
                viewModel.adapter.vList.addAll(viewModel.tempListMulti)
                viewModel.adapterPosition = viewModel.tempPositionMulti
                viewModel.tempListMulti.clear()

                ioScope().launch {
                    viewModel.pages = viewModel.getPages(FOR_MULTI, activity.reddit, subredditName, sorting, multiName)
                    if (viewModel.adapter.vList.isEmpty()) {
                        viewModel.loadMoreData(viewModel.pages!!)
                    }
                }
            }
        }

        view_pager_main.adapter = viewModel.adapter
        view_pager_main.doOnPreDraw {
            view_pager_main.currentItem = viewModel.adapterPosition
        }

        viewModel.isRefreshing.observe(viewLifecycleOwner) {
            layout_refresh.isRefreshing = it
        }
        viewModel.videosExhausted.observe(viewLifecycleOwner) {
            if (it) {
                shortToast(activity, "All videos loaded")
            }
        }

        viewModel.commentsArray.observe(viewLifecycleOwner) {
            if (it != null && this::commentsView.isInitialized) {
                val childLayout2 = LinearLayout(activity)
                val params = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                params.setMargins(10, 10, 10, 10)
                childLayout2.layoutParams = params
                addCommentView(it, 10F, commentsView.comments_layout, true)
                commentsView.shimmer_rc.hide()
            }
        }

        chip_group_choose_feed.setOnCheckedStateChangeListener { group, _ ->
            when (group.checkedChipId) {
                R.id.chip_front_page -> {
                    activity.pauseAllPlayers()
                    chip_front_page.setChipBackgroundColorResource(R.color.orange)
                    chip_popular.setChipBackgroundColorResource(R.color.chipBg)
                    viewModel.tempListPop.clear()
                    viewModel.tempListPop.addAll(viewModel.adapter.vList)
                    viewModel.tempPositionPop = view_pager_main.currentItem
                    viewModel.tempPagesPop = viewModel.pages
                    viewModel.adapter.vList.clear()
                    viewModel.adapter.notifyDataSetChanged()
                    if (viewModel.tempListFront.isNotEmpty()) {
                        viewModel.adapter.vList.addAll(viewModel.tempListFront)
                        viewModel.pages = viewModel.tempPageFront
                        view_pager_main.setCurrentItem(viewModel.tempPositionFront, true)
                    } else {
                        job?.cancel()
                        job = ioScope().launch {
                            viewModel.pages = viewModel.getPages(FOR_MAIN, activity.reddit)
                            viewModel.loadMoreData(viewModel.pages!!)
                        }
                    }
                    viewModel.adapter.content = FRONT_PAGE
                }

                R.id.chip_popular -> {
                    activity.pauseAllPlayers()
                    chip_popular.setChipBackgroundColorResource(R.color.orange)
                    chip_front_page.setChipBackgroundColorResource(R.color.chipBg)
                    viewModel.tempListFront.clear()
                    viewModel.tempListFront.addAll(viewModel.adapter.vList)
                    viewModel.tempPositionFront = view_pager_main.currentItem
                    viewModel.tempPageFront = viewModel.pages
                    viewModel.adapter.vList.clear()
                    viewModel.adapter.notifyDataSetChanged()
                    if (viewModel.tempListPop.isNotEmpty()) {
                        viewModel.adapter.vList.addAll(viewModel.tempListPop)
                        viewModel.pages = viewModel.tempPagesPop
                        view_pager_main.setCurrentItem(viewModel.tempPositionPop, true)
                    } else {
                        job?.cancel()
                        job = ioScope().launch {
                            viewModel.pages = viewModel.getPages(FOR_SUBREDDIT, activity.reddit, "popular")
                            viewModel.loadMoreData(viewModel.pages!!)
                        }
                    }
                    viewModel.adapter.content = POPULAR
                }
            }
        }

        viewModel.goToTop.observe(viewLifecycleOwner) {
            if (it) view_pager_main.setCurrentItem(0, true)
        }

        layout_refresh.setOnRefreshListener {
            Log.d(TAG, "onViewCreated: manual refresh")
            viewModel.pages?.let { viewModel.loadMoreData(it, true) }
        }
    }

    private fun addCommentView(commentsArray: JsonArray?, margin: Float, parentLayout: LinearLayout, isMainLayout: Boolean = false) {
        commentsArray?.forEach { comment ->
            var replies: JsonArray? = null
            val layout = LinearLayout(activity)
            layout.layoutTransition = LayoutTransition()
            layout.orientation = LinearLayout.VERTICAL
            val params = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

            val r = activity.resources
            val pxLeft = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                margin,
                r.displayMetrics
            ).toInt()

            val px = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                10F,
                r.displayMetrics
            ).toInt()
            params.setMargins(pxLeft, px * 2, 0, px)
            layout.layoutParams = params
            layout.background = activity.getDrawable(R.drawable.reddit_indent)
            ///////////////////////ADD LAYOUT ONLY AFTER BODY IS NOT NULL
            ////////////////////////////////////////////////////////////////////////
            if (comment.isJsonObject) {
                val data = comment.asJsonObject["data"].asJsonObject
                val author = try {
                    data["author"].asString
                } catch (e: Exception) {
                    "null"
                }
                val dateCreated = try {
                    data["created_utc"].asLong
                } catch (e: Exception) {
                    0L
                }
                val score = try {
                    data["score"].asString
                } catch (e: Exception) {
                    "null"
                }
                val body = try {
                    data["body"].asString
                } catch (e: Exception) {
                    return
                }

                parentLayout.addView(layout)
                ///////////////////////////////////////////////////// ADD VIEW TO THE LAYOUT
                if (author != "null") {
                    val tvAuthor = TextView(activity)
                    tvAuthor.setTextIsSelectable(true)
                    tvAuthor.setPadding(px, 0, 0, 0)
                    tvAuthor.text = "u/" + author + " • " + dateCreated.toTimeAgo()
                    tvAuthor.textSize = 12F
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        tvAuthor.setTypeface(null, Typeface.BOLD)
                    }

                    val iv = ShapeableImageView(activity)
                    val ivParams = LinearLayout.LayoutParams(24F.toDp(), 24F.toDp())
                    ivParams.setMargins(px, 0, 0, 0)
                    iv.layoutParams = ivParams
                    iv.shapeAppearanceModel = iv.shapeAppearanceModel
                        .toBuilder()
                        .setAllCornerSizes(24F)
                        .build()
                    ioScope().launch {
                        val icon = getUserIcon(author, activity.client)
                        mainScope().launch {
                            Glide.with(activity)
                                .load(icon)
                                .into(iv)
                        }
                    }

                    val ll = LinearLayout(activity)
                    ll.setVerticalGravity(Gravity.CENTER_VERTICAL)
                    ll.orientation = LinearLayout.HORIZONTAL

                    ll.addView(iv)
                    ll.addView(tvAuthor)

                    if (author.lowercase() != "automoderator" && !author.lowercase().endsWith("bot")) {
                        layout.addView(ll)
                    }
                }

                if (body != "null") {
                    val tvBody = TextView(activity)
                    tvBody.setPadding(px, 0, 0, 0)
                    tvBody.text = body.replace("amp;", "").trim()
                    tvBody.setTextIsSelectable(true)
                    Linkify.addLinks(tvBody, Linkify.WEB_URLS)
                    tvBody.textSize = 18F
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        tvBody.setTypeface(null, Typeface.BOLD)
                    }
                    if (author.lowercase() != "automoderator" && !author.lowercase().endsWith("bot")) {
                        layout.addView(tvBody)
                    }

                }

                if (score != "null") {
                    val tvScore = TextView(activity)
                    tvScore.setPadding(px, px, 0, 0)
                    tvScore.text = "upvotes: " + score
                    tvScore.textSize = 12F
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        tvScore.setTypeface(null, Typeface.BOLD)
                    }
                    if (author.lowercase() != "automoderator" && !author.lowercase().endsWith("bot")) {
                        layout.addView(tvScore)
                    }
                }

                /////////////////////////////////////////////////////
                replies = try {
                    data["replies"].asJsonObject["data"].asJsonObject["children"].asJsonArray
                } catch (e: java.lang.Exception) {
                    null
                }

                addCommentView(replies, 20F, layout)
            }

            if (replies != null) {
                if (!isMainLayout) {
                    val tv = TextView(activity)
                    tv.setPadding(px, px, 0, 0)
                    tv.text = "Hide replies"
                    tv.textSize = 12F
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        tv.setTypeface(null, Typeface.ITALIC)
                    }
                    tv.setTextColor(activity.getColor(android.R.color.holo_red_light))

                    parentLayout.addView(tv)

                    tv.setOnClickListener {
                        layout.apply {
                            visibility = if (isVisible) {
                                tv.text = "Show replies..."
                                tv.setTextColor(activity.getColor(android.R.color.holo_green_light))
                                View.GONE
                            } else {
                                tv.text = "Hide replies"
                                tv.setTextColor(activity.getColor(android.R.color.holo_red_light))
                                View.VISIBLE
                            }
                        }
                    }

                    runAfter(200) { tv.performClick() }
                }

            }
        }
    }

    override fun onPause() {
        Log.d(TAG, "onPause: called")
        activity.pauseAllPlayers()
        super.onPause()
    }

    override fun onResume() {
        activity.window.setLayout(ConstraintLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        super.onResume()
    }

    override fun onDestroyView() {
        viewModel.adapterPosition = view_pager_main.currentItem

        when (calledFor) {
            FOR_MAIN -> {
                viewModel.tempPosition = view_pager_main.currentItem
                viewModel.tempList.clear()
                viewModel.tempList.addAll(viewModel.adapter.vList)
                viewModel.tempPages = viewModel.pages
            }

            FOR_MULTI -> {
                viewModel.tempPositionMulti = view_pager_main.currentItem
                viewModel.tempListMulti.clear()
                viewModel.tempListMulti.addAll(viewModel.adapter.vList)
                viewModel.tempPagesMulti = viewModel.pages
            }
        }

        activity.pauseAllPlayers()
        activity.playerList.forEach {
            it.release()
        }
        activity.playerList.clear()
        super.onDestroyView()
    }

    override fun onLoadMoreData() {
        viewModel.job?.let { job ->
            if (!job.isActive) {
                viewModel.pages?.let { viewModel.loadMoreData(it) }
            }
        }
    }

    override fun onStartDownloading(post: Submission?, holder: VideoAdapter.VideoViewHolder?, aboutPost: AboutPost?, bsdView: View?) {}

    interface OnFragmentStateChanged {
        fun pauseAllPlayers()
    }

    override fun onHideChips() {
        when (calledFor) {
            FOR_MAIN -> chip_group_choose_feed.hide()
            FOR_SUBREDDIT -> chip_sr.hide()
            FOR_MULTI -> chip_multi.hide()
        }
    }

    override fun onShowChips() {
        when (calledFor) {
            FOR_MAIN -> {
                if (activity.reddit.authManager.currentUsername() != USER_LESS) {
                    chip_group_choose_feed.show()
                }
            }
            FOR_SUBREDDIT -> chip_sr.show()
            FOR_MULTI -> chip_multi.show()
        }
    }

    override fun showComments(permalink: String) {
        val sheet = BottomSheetDialog(activity)
        commentsView = LayoutInflater.from(activity).inflate(R.layout.bottom_sheet_comments, null, false)
        sheet.setContentView(commentsView)
        sheet.show()
        commentsView.shimmer_rc.show()
        viewModel.getComments(permalink, activity.client)
    }

    private fun Float.toDp(): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics
        ).toInt()
    }
}