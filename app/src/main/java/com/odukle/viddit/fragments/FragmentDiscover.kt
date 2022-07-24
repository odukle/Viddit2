package com.odukle.viddit.fragments

import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.chip.Chip
import com.google.android.material.imageview.ShapeableImageView
import com.google.android.material.shape.CornerFamily
import com.google.android.material.textfield.TextInputEditText
import com.google.common.base.CharMatcher
import com.google.gson.JsonParser
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.adapters.SearchAdapter
import com.odukle.viddit.models.MultiReddit
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.bottomsheet_cf.*
import kotlinx.android.synthetic.main.bottomsheet_cf.view.*
import kotlinx.android.synthetic.main.fragment_discover.*
import kotlinx.coroutines.launch

private const val TAG = "FragmentDiscover"

class FragmentDiscover : Fragment(), SearchAdapter.OnShowCustomFeeds {

    companion object {
        fun newInstance() = FragmentDiscover()
    }

    private lateinit var viewModel: DiscoverViewModel
    private lateinit var activity: MainActivity
    private var bottomSheetDialog: BottomSheetDialog? = null
    private var bottomSheetView: View? = null
    private lateinit var subredditToAdd: String

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_discover, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        activity = requireActivity() as MainActivity
        viewModel = ViewModelProvider(activity)[DiscoverViewModel::class.java]
        rv_search.layoutManager = LinearLayoutManager(activity)

        if (viewModel.rList.value?.isNotEmpty() == true) {
            rv_search.adapter = SearchAdapter(viewModel.rList.value!!)
            card_loading.hide()
        } else {
            if (isOnline(activity)) {
                ioScope().launch {
                    viewModel.getTopSubreddits(activity.client)
                }
            } else showNoInternetToast(activity)

        }

        viewModel.rList.observe(viewLifecycleOwner) {
            if (it.isNotEmpty()) {
                rv_search.adapter = SearchAdapter(it)
                card_loading.hide()
            }
        }

        chip_group_discover.setOnCheckedStateChangeListener { group, checkedIds ->
            val chip = group.findViewById<Chip>(group.checkedChipId)
            if (chip != null) {
                val query = chip.text.toString()
                et_search.text?.clear()
                ioScope().launch {
                    card_loading.show()
                    if (query == "videos") {
                        if (isOnline(activity)) viewModel.getTopSubreddits(activity.client)
                        else showNoInternetToast(activity)
                    } else {
                        if (isOnline(activity)) viewModel.searchSubreddits(query, nsfwAllowed(activity), activity.client)
                        else showNoInternetToast(activity)
                    }
                }
            }
        }

        et_search.setOnEditorActionListener { v, _, _ ->
            if (v.text.isNullOrEmpty()) return@setOnEditorActionListener false

            val query = (v as TextInputEditText).text.toString()
            ioScope().launch {
                card_loading.show()
                if (isOnline(activity)) viewModel.searchSubreddits(query, nsfwAllowed(activity), activity.client)
                else showNoInternetToast(activity)
            }

            v.clearFocus()
            chip_group_discover.clearCheck()
            false
        }

        btn_search.setOnClickListener {
            btn_search.bounce()
            et_search.onEditorAction(EditorInfo.IME_ACTION_DONE)
        }

        switch_nsfw_discover.isChecked = nsfwAllowed(activity)
        switch_nsfw_discover.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                allowNSFW(activity)
                if (!et_search.text.isNullOrEmpty()) btn_search.performClick()

            } else {
                doNotAllowNSFW(activity)
                if (!et_search.text.isNullOrEmpty()) btn_search.performClick()
            }
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

    override fun onResume() {
        activity.window.setLayout(ConstraintLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        super.onResume()
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

    override fun onShowCustomFeeds(subredditName: String) {
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

            viewModel.multiReddit.observe(this@FragmentDiscover) {
                if (it != null) {
                    addFeedToBottomSheet(it, subredditName)
                }
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
            shortToast(activity, "Adding..")
            if (isOnline(activity)) viewModel.addSubRedditToCf(activity.reddit, multiReddit.name, subredditName)
            else showNoInternetToast(activity)
        }

        bottomSheetView?.apply {
            layout_cf.addView(ll)
        }
    }

    private fun Float.toDp(): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            this,
            activity.resources.displayMetrics
        ).toInt()
    }

}

