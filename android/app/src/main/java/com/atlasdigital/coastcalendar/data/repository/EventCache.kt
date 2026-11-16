package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.LocalEvent
import java.util.concurrent.ConcurrentHashMap

/** Last-loaded listings by id, so a detail route can open the same LocalEvent the list showed (iOS passes the value). */
class EventCache {
    private val events = ConcurrentHashMap<String, LocalEvent>()
    fun put(list: List<LocalEvent>) = list.forEach { events[it.id] = it }
    fun put(event: LocalEvent) { events[event.id] = event }
    operator fun get(id: String): LocalEvent? = events[id]
}
