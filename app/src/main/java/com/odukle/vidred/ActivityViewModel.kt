package com.odukle.vidred

import androidx.lifecycle.ViewModel
import net.dean.jraw.models.Submission
import net.dean.jraw.pagination.DefaultPaginator

class ActivityViewModel : ViewModel() {
    var srPages: DefaultPaginator<Submission>? = null
    var prevSubredditName = ""
    val vList = mutableListOf<Submission>()
    var srPosition: Int = 0
    var content = "main"
}