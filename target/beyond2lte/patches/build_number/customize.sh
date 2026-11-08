# crew: Settings > Software information > Build number = "StellarRomV2.0 (<S24 FE base build>)".
# The base build is read from the source firmware (SM-S721B), never hardcoded.
# ro.build.display.id is set in several build.props (system, system_ext,
# product...) and init keeps the LAST one loaded (product wins), so patch all.
BN_ROM="StellarRomV2.0"
BN_SRC=""
CREW_SRC_SHORT="${SOURCE_FIRMWARE_PATH:-SM-S721B_EUX}"; CREW_SRC_SHORT="${CREW_SRC_SHORT%%_*}"; CREW_SRC_SHORT="${CREW_SRC_SHORT#SM-}"
BN_RX="^${CREW_SRC_SHORT}[A-Z0-9]{6,}\$"
for BN_PROP in "$FW_DIR"/SM-${CREW_SRC_SHORT}_*/system/system/build.prop "$WORK_DIR/system/system/build.prop"; do
    [ -f "$BN_PROP" ] || continue
    for BN_KEY in ro.system.build.version.incremental ro.build.version.incremental; do
        BN_V="$(grep -m1 "^$BN_KEY=" "$BN_PROP" | cut -d= -f2-)"
        if [[ "$BN_V" =~ $BN_RX ]]; then BN_SRC="$BN_V"; break 2; fi
    done
    BN_V="$(grep -m1 '^ro\.\(system\.\)\?build\.display\.id=' "$BN_PROP" | cut -d= -f2- | tr ' .()' '\n' | grep -m1 -E "$BN_RX" || true)"
    if [ -n "$BN_V" ]; then BN_SRC="$BN_V"; break; fi
done
if [ -n "$BN_SRC" ]; then
    BN_ID="$BN_ROM ($BN_SRC)"
else
    LOGW "$CREW_SRC_SHORT base build not found in source firmware, using \"$BN_ROM\" only"
    BN_ID="$BN_ROM"
fi
LOG "- Build number: $BN_ID"
SET_PROP "system" "ro.build.display.id" "$BN_ID"
while IFS= read -r BN_FILE; do
    sed -i -E "s|^(ro\.([a-z_]+\.)?build\.display\.id)=.*|\1=$BN_ID|" "$BN_FILE"
    LOG "  - $(grep -hE '^ro\.([a-z_]+\.)?build\.display\.id=' "$BN_FILE" | tr '\n' ' ')in ${BN_FILE//$WORK_DIR/}"
done < <(grep -rlE --include='*.prop' '^ro\.([a-z_]+\.)?build\.display\.id=' "$WORK_DIR" 2>/dev/null)
unset CREW_SRC_SHORT BN_ROM BN_SRC BN_RX BN_PROP BN_KEY BN_V BN_ID BN_FILE
