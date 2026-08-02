const markerPath = `${process.env.HOME}/Library/Application Support/DontDieOnMeNow/opencode-waiting`
const allActiveTasksMode = "allActiveTasks"

async function readMarker() {
  try {
    const contents = await Bun.file(markerPath).text()
    const fields = Object.fromEntries(
      contents
        .split("\n")
        .map((line) => line.split("=", 2))
        .filter(([key, value]) => key && value)
    )

    if (fields.status !== "armed" || !fields.token) {
      return null
    }

    return {
      ...fields,
      mode: fields.mode === allActiveTasksMode ? allActiveTasksMode : "firstTask",
    }
  } catch {
    return null
  }
}

export const DontDieOnMeNow = async ({ $ }) => {
  let activeToken = null
  let trackedSessionIDs = new Set()
  let completedSessionIDs = new Set()
  let observedSession = false
  let hadError = false
  let finished = false

  function resetTracking(token) {
    activeToken = token
    trackedSessionIDs = new Set()
    completedSessionIDs = new Set()
    observedSession = false
    hadError = false
    finished = false
  }

  async function currentMarker() {
    const marker = await readMarker()
    const token = marker?.token ?? null
    if (token !== activeToken) {
      resetTracking(token)
    }
    return marker
  }

  async function notify(marker, sessionIDs, outcome) {
    if (!marker || finished) {
      return
    }

    finished = true
    const current = await readMarker()
    if (!current || current.token !== marker.token) {
      return
    }

    const url = new URL("dont-die-on-me-now://opencode-finished")
    url.searchParams.set("token", marker.token)
    const sessionValue = [...new Set(sessionIDs)].filter(Boolean).join(",")
    if (sessionValue) {
      url.searchParams.set("session", sessionValue)
    }
    url.searchParams.set("outcome", outcome)

    try {
      await $`/usr/bin/open -g ${url.toString()}`
    } catch (error) {
      console.error("Don't Die On Me Now could not notify the app:", error)
    }
  }

  async function notifyWhenAllTasksFinish(marker) {
    if (
      marker.mode !== allActiveTasksMode ||
      trackedSessionIDs.size > 0 ||
      !observedSession ||
      finished
    ) {
      return
    }

    if (completedSessionIDs.size === 0 && !hadError) {
      resetTracking(marker.token)
      return
    }

    await notify(
      marker,
      [...completedSessionIDs],
      hadError ? "error" : "success"
    )
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.status") {
        if (event.properties.status.type !== "busy") {
          return
        }

        const marker = await currentMarker()
        const sessionID = event.properties.sessionID
        if (!marker || !sessionID || finished) {
          return
        }

        if (marker.mode === allActiveTasksMode || trackedSessionIDs.size === 0) {
          trackedSessionIDs.add(sessionID)
          observedSession = true
        }
        return
      }

      if (event.type === "session.error") {
        const marker = await currentMarker()
        const sessionID = event.properties.sessionID
        if (!marker || !sessionID || !trackedSessionIDs.has(sessionID) || finished) {
          return
        }

        trackedSessionIDs.delete(sessionID)
        if (event.properties.error?.name === "MessageAbortedError") {
          if (marker.mode === allActiveTasksMode) {
            await notifyWhenAllTasksFinish(marker)
          } else {
            resetTracking(marker.token)
          }
          return
        }

        completedSessionIDs.add(sessionID)
        hadError = true
        if (marker.mode === allActiveTasksMode) {
          await notifyWhenAllTasksFinish(marker)
        } else {
          await notify(marker, [sessionID], "error")
        }
        return
      }

      if (event.type === "session.idle") {
        const marker = await currentMarker()
        const sessionID = event.properties.sessionID
        if (!marker || !sessionID || !trackedSessionIDs.has(sessionID) || finished) {
          return
        }

        trackedSessionIDs.delete(sessionID)
        completedSessionIDs.add(sessionID)

        if (marker.mode === allActiveTasksMode) {
          await notifyWhenAllTasksFinish(marker)
        } else {
          await notify(marker, [sessionID], "success")
        }
      }
    },
  }
}
