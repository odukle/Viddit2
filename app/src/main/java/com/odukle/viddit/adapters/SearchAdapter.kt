package com.odukle.viddit.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.fragments.FragmentCustomFeeds
import com.odukle.viddit.fragments.FragmentDiscover
import com.odukle.viddit.fragments.SubredditFragment
import com.odukle.viddit.models.MultiReddit
import com.odukle.viddit.utils.getCurrentFragment
import kotlinx.android.synthetic.main.item_view_search.view.*

class SearchAdapter(private val rList: MutableList<Pair<String, String>>, private val multiReddit: MultiReddit? = null) :
    RecyclerView.Adapter<SearchAdapter.SearchViewHolder>() {

    private lateinit var activity: MainActivity

    inner class SearchViewHolder(view: View) : RecyclerView.ViewHolder(view) {

    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SearchViewHolder {
        activity = parent.context as MainActivity

        val view = LayoutInflater.from(activity).inflate(R.layout.item_view_search, parent, false)
        return SearchViewHolder(view)
    }

    override fun onBindViewHolder(holder: SearchViewHolder, position: Int) {
        val pair = rList[position]
        val name = pair.second.replace("r/", "")
        val namePrefixed = pair.second
        val icon = pair.first
        holder.itemView.apply {
            tv_subreddit_title.text = namePrefixed
            Glide.with(this)
                .load(icon)
                .placeholder(R.drawable.ic_reddit)
                .into(iv_icon)

            card_subreddit.setOnClickListener {
                activity.onOpenFragment(SubredditFragment.newInstance(name))
            }

            if (getCurrentFragment(activity) is FragmentCustomFeeds) chip_add_or_remove.text = activity.getString(R.string.remove)
            chip_add_or_remove.setOnClickListener {
                when (val fragment = getCurrentFragment(activity)) {
                    is FragmentDiscover -> fragment.onShowCustomFeeds(name)
                    is FragmentCustomFeeds -> {
                        multiReddit?.let { fragment.onRemoveSubreddit(name, multiReddit) }
                    }
                }
            }
        }
    }

    override fun getItemCount(): Int {
        return rList.size
    }

    interface OnShowCustomFeeds {
        fun onShowCustomFeeds(subredditName: String)
    }

    interface OnRemoveSubreddit {
        fun onRemoveSubreddit(subredditName: String, multiReddit: MultiReddit)
    }
}