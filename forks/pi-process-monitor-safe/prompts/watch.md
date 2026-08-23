Start a non-blocking watcher with the source below and the default notifyOn (milestones and failures). Report the watcher id, then keep working. Do not block waiting. I'll be pinged when a milestone hits, a failure occurs, or the process dies.

Source:
$ARGUMENTS

After starting, tell me the watcher id, the mode (spawn/poll/file), and what it will ping on. Then continue with whatever else we were doing. If the start fails because 16 monitors are already active, run monitor_status, stop stale watchers with monitor_kill (id "*" stops all), and retry. Watchers do not survive a session shutdown or /reload, so restart any you still need.
