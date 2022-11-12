package com.odukle.vidred.models

class MultiReddit (
    val name: String,
    val displayName: String,
    val iconUrl: String,
    val subreddits: MutableList<String>,
)