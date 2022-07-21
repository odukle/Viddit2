package com.odukle.viddit.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.google.gson.JsonParser
import com.odukle.viddit.utils.ioScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.SocketTimeoutException

private const val TAG = "UserViewModel"

class UserViewModel : ViewModel() {

    private val _userIcon = MutableLiveData<String>("")
    val userIcon: LiveData<String> = _userIcon

    fun getUserIcon(user: String, client: OkHttpClient) {
        ioScope().launch {
            try {
                val request = Request.Builder()
                    .url("https://www.reddit.com/user/$user/about/.json")
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                val json = response.body?.string()
                val jsonObject = JsonParser.parseString(json).asJsonObject
                val data = jsonObject["data"].asJsonObject
                _userIcon.postValue(data["icon_img"].asString.replace("amp;", ""))
            } catch (e: Exception) {
                if (e !is SocketTimeoutException) {
                    Log.e(TAG, "getSubreddits: ${e.stackTraceToString()}")
                }
                _userIcon.postValue("")
            }
        }

    }

}