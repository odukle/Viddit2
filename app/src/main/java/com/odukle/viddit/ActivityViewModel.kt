package com.odukle.viddit

import androidx.lifecycle.LiveData
import androidx.lifecycle.ViewModel
import com.odukle.viddit.adapters.SubredditAdapter
import net.dean.jraw.models.Submission
import net.dean.jraw.pagination.DefaultPaginator
import net.dean.jraw.references.SubredditReference

class ActivityViewModel : ViewModel() {
    var pages: DefaultPaginator<Submission>? = null
    var subredditRef: SubredditReference? = null
    var prevSubredditName = ""
    val vList = mutableListOf<Submission>()
    var srPosition: Int = 0
    var content = "main"
}