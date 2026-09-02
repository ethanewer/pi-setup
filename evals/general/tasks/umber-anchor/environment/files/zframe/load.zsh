# load.zsh — light zsh framework loader (self-authored, clean-room).
# Reads ZSH_THEME and the `plugins` array set by the calling rc, then activates
# the named theme and each named plugin from $FRAMEWORK_DIR. Exposes
# $THEME_STATUS and $PLUGIN_STATUS so a caller can confirm activation.
[[ -n "$ZFRAME" ]] || ZFRAME="/app/zframe"

typeset -ga PLUGINS_LOADED
THEME_STATUS="inactive"
if [[ -n "$ZSH_THEME" && -f "$ZFRAME/themes/$ZSH_THEME.plugin.zsh" ]]; then
    source "$ZFRAME/themes/$ZSH_THEME.plugin.zsh"
    THEME_STATUS="active:$ZSH_THEME"
else
    THEME_STATUS="active:$ZSH_THEME:missing"
fi
export THEME_STATUS

for _p in "${plugins[@]}"; do
    if [[ -f "$ZFRAME/plugins/$_p.plugin.zsh" ]]; then
        source "$ZFRAME/plugins/$_p.plugin.zsh"
        PLUGINS_LOADED+=("$_p")
    else
        PLUGINS_LOADED+=("$_p:missing")
    fi
done
PLUGIN_STATUS="${(j:,:)PLUGINS_LOADED}"
export PLUGIN_STATUS