package com.odukle.viddit.fragments

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.doOnPreDraw
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.utils.*
import com.squareup.moshi.Types
import kotlinx.android.synthetic.main.fragment_home.*
import kotlinx.coroutines.launch
import net.dean.jraw.JrawUtils
import net.dean.jraw.models.Submission
import java.lang.reflect.Type
import kotlin.properties.Delegates

private const val TAG = "FragmentHome"

class FragmentHome : Fragment(), VideoAdapter.OnAdapterCallback {

    companion object {
        fun newInstance(
            loadFrontPage: Boolean = true,
            jsonList: String = "",
            adapterPosition: Int = 0,
            subredditName: String = "",
            sorting: String = HOT,
        ) = FragmentHome().apply {
            arguments = Bundle().apply {
                putBoolean(LOAD_FRONT_PAGE, loadFrontPage)
                putString(JSON_LIST, jsonList)
                putInt(ADAPTER_POSITION, adapterPosition)
                putString(SUBREDDIT_NAME, subredditName)
                putString(SORTING, sorting)
            }
        }
    }

    private lateinit var viewModel: HomeViewModel
    private lateinit var activity: MainActivity
    private var loadFrontPage by Delegates.notNull<Boolean>()
    private lateinit var jsonList: String
    private var adapterPosition by Delegates.notNull<Int>()
    private lateinit var subredditName: String
    private lateinit var sorting: String

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        loadFrontPage = requireArguments().getBoolean(LOAD_FRONT_PAGE)
        jsonList = requireArguments().getString(JSON_LIST, "")
        adapterPosition = requireArguments().getInt(ADAPTER_POSITION)
        subredditName = requireArguments().getString(SUBREDDIT_NAME, "")
        sorting = requireArguments().getString(SORTING, HOT)
        return inflater.inflate(R.layout.fragment_home, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        Log.d(TAG, "onViewCreated: called")
        activity = requireActivity() as MainActivity
        viewModel = ViewModelProvider(activity)[HomeViewModel::class.java]

        if (!loadFrontPage) {
            ioScope().launch {
                viewModel.pages = viewModel.getPages(activity.reddit, subredditName, sorting)
            }
            val type: Type = Types.newParameterizedType(
                MutableList::class.java,
                Submission::class.java
            )

            val jsonAdapter = JrawUtils.moshi.adapter<MutableList<Submission>>(type).serializeNulls()
            val vList = jsonAdapter.fromJson(jsonList)
            if (vList != null) {
                val submission = vList[adapterPosition]
                vList.toMutableList<Any>().placeAds()
                adapterPosition = vList.indexOf(submission)
            }
            viewModel.adapter.vList = vList as MutableList<Any>
            viewModel.adapterPosition = adapterPosition
        } else if (viewModel.tempList.isNotEmpty()) {
            Log.d(TAG, "onViewCreated: not Empty")
            viewModel.adapter.vList.clear()
            viewModel.adapter.vList.addAll(viewModel.tempList)
            viewModel.adapterPosition = viewModel.tempPosition
            viewModel.tempList.clear()
        }

        view_pager_main.adapter = viewModel.adapter
        view_pager_main.doOnPreDraw {
            view_pager_main.currentItem = viewModel.adapterPosition
        }

        activity.redditLive.observe(viewLifecycleOwner) {
            if (viewModel.adapter.vList.isEmpty()) {
                ioScope().launch {
                    viewModel.pages = viewModel.getPages(it, subredditName, sorting)
                    viewModel.loadMoreData(viewModel.pages!!)
                }
            }
        }

        viewModel.isRefreshing.observe(viewLifecycleOwner) {
            layout_refresh.isRefreshing = it
        }
        viewModel.videosExhausted.observe(viewLifecycleOwner) {
            if (it) {
                shortToast(activity, "All videos loaded")
            }
        }
    }

    override fun onPause() {
        Log.d(TAG, "onPause: called")
        activity.pauseCurrentPlayer()
        super.onPause()
    }

    override fun onResume() {
        activity.window.setLayout(ConstraintLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        super.onResume()
    }

    override fun onDestroyView() {
        viewModel.adapterPosition = view_pager_main.currentItem
        if (loadFrontPage) {
            viewModel.tempPosition = view_pager_main.currentItem
            viewModel.tempList.clear()
            viewModel.tempList.addAll(viewModel.adapter.vList)
        }
        activity.pauseCurrentPlayer()
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

    interface OnFragmentStateChanged {
        fun pauseCurrentPlayer()
    }
}