Start a non-blocking watcher with the source below and default notifyOn (milestones + failures). Report the watcher id, then keep working — do NOT block waiting. I'll be pinged when a milestone hits, a failure occurs, or the process dies.

Source:
$ARGUMENTS

After starting, tell me the watcher id, the mode (spawn/poll/file), and what it will ping on. Then continue with whatever else we were doing. If the start fails because 16 monitors are already active, run monitor_status and stop stale watchers with monitor_kill or monitor_kill_all, then retry. Remember: watchers do not survive session shutdown or /reload.
