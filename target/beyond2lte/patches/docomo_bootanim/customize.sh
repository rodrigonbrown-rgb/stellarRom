CREW_BA_SET="$(cat "$MODPATH/blobs/active" 2>/dev/null || echo sc04l)"
CREW_BA_SRC="$MODPATH/blobs/$CREW_BA_SET"
CREW_BA_DST="$WORK_DIR/system/system/media"
if [ ! -d "$CREW_BA_SRC" ]; then
    echo "docomo_bootanim: set $CREW_BA_SET missing" >&2
    exit 1
fi
for CREW_BA in bootsamsung.qmg bootsamsungloop.qmg shutdown.qmg; do
    [ -f "$CREW_BA_SRC/$CREW_BA" ] || continue
    if [ ! -f "$CREW_BA_DST/$CREW_BA" ]; then
        echo "docomo_bootanim: $CREW_BA not in work_dir (no metadata entry)" >&2
        exit 1
    fi
    install -m 0644 "$CREW_BA_SRC/$CREW_BA" "$CREW_BA_DST/$CREW_BA"
    echo "docomo_bootanim: $CREW_BA_SET/$CREW_BA replaced"
done
