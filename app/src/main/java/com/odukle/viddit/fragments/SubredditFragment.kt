package com.odukle.viddit.fragments

import android.annotation.SuppressLint
import androidx.lifecycle.ViewModelProvider
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.bumptech.glide.Glide
import com.google.android.material.chip.Chip
import com.odukle.viddit.ActivityViewModel
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.adapters.SubredditAdapter
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.fragment_subreddit.*
import kotlinx.coroutines.launch
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
        if (subredditName != activityViewModel.prevSubredditName) {
            activityViewModel.prevSubredditName = subredditName
            activityViewModel.vList.clear()
            activityViewModel.vList.addAll(viewModel.adapter.vList)
        } else {
            viewModel.adapter.vList.clear()
            viewModel.adapter.vList.addAll(activityViewModel.vList)
            viewModel.pages.postValue(activityViewModel.pages)
        }
        rv_subreddit.adapter = viewModel.adapter

        showShimmer()
        ioScope().launch {
            viewModel.getSubredditRef(activity.reddit, subredditName)
        }

        viewModel.subredditRef.observe(viewLifecycleOwner) { srf ->
            activityViewModel.subredditRef = srf
            if (viewModel.adapter.vList.isEmpty()) {
                srf?.let { viewModel.getSRPages(it) }
            }
        }

        viewModel.pages.observe(viewLifecycleOwner) {
            activityViewModel.pages = it
            viewModel.adapter.vList.clear()
            viewModel.adapter.notifyDataSetChanged()
            if (it != null) {
                progress_bar_sr.show()
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

        viewModel.isRefreshing.observe(viewLifecycleOwner) {
            if (it) progress_bar_sr.show()
            else progress_bar_sr.hide()
        }

        viewModel.videosExhausted.observe(viewLifecycleOwner) {
            if (it) {
                shortToast(activity, "All videos loaded from $subredditName")
            }
        }

        viewModel.dataLoaded.observe(viewLifecycleOwner) {
            if (it) {
                runAfter(100) {
                    rv_subreddit.smoothScrollToPosition(0)
                }
            }
        }

        chip_group.setOnCheckedStateChangeListener { group, checkedIds ->
            val chip = group.findViewById<Chip>(checkedIds[0])
            if (chip != null) {
                val order = chip.tag as String
                if (chip.id != chip_top.id) {
                    viewModel.subredditRef.value?.let { viewModel.getSRPages(it, getSubredditSort(order)) }
                    chip_group_time.hide()
                    chip_group_time.clearCheck()
                    chip_top.text = "Top"
                }
            }
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
        activityViewModel.srPosition = (rv_subreddit.layoutManager as CustomGLM).findLastCompletelyVisibleItemPosition()
        super.onDestroyView()
    }

    override fun onLoadMoreDataSR() {
        val runnable = kotlinx.coroutines.Runnable {
            if (viewModel.videosExhausted.value == false) {
                viewModel.pages.value?.let { viewModel.loadMoreDataSR(it) }
            }
        }
        viewModel.job?.let { job ->
            if (!job.isActive) {
                runnable.run()
            }
        } ?: runnable.run()
    }
}