# ro.build.display.id is set in several build.props (system, system_ext,
# product...) and init keeps the LAST one loaded (product wins), so patch all.
BN_ID="${TARGET_ROM_DISPLAY_ID:-ExtremeRom-Revived-crew}"
LOG "- Build number: $BN_ID"
SET_PROP "system" "ro.build.display.id" "$BN_ID"
while IFS= read -r BN_FILE; do
    sed -i -E "s|^(ro\.([a-z_]+\.)?build\.display\.id)=.*|\1=$BN_ID|" "$BN_FILE"
    LOG "  - $(grep -hE '^ro\.([a-z_]+\.)?build\.display\.id=' "$BN_FILE" | tr '\n' ' ')in ${BN_FILE//$WORK_DIR/}"
done < <(grep -rlE --include='*.prop' '^ro\.([a-z_]+\.)?build\.display\.id=' "$WORK_DIR" 2>/dev/null)
unset BN_ID BN_FILE
