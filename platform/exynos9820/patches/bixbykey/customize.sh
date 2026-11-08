BK_KL="$WORK_DIR/system/system/usr/keylayout/Generic_internal.kl"
LOG "- Setting key code 703 to VOICE_ASSIST"
if [ -f "$BK_KL" ]; then
    sed -i "s/WINK/VOICE_ASSIST/g" "$BK_KL"
    if grep -qE '^key[[:space:]]+703[[:space:]]' "$BK_KL"; then
        sed -i -E 's/^(key[[:space:]]+703[[:space:]]+)[A-Z_0-9]+/\1VOICE_ASSIST/' "$BK_KL"
    else
        printf 'key 703   VOICE_ASSIST\n' >> "$BK_KL"
    fi
    LOG "- $(grep -E '^key[[:space:]]+703' "$BK_KL")"
else
    LOGW "Generic_internal.kl not found, Bixby key left unmapped"
fi
unset BK_KL
