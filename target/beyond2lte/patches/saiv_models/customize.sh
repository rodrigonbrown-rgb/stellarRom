SKIPUNZIP=1
# crew: Gallery / image-understanding models matching the One UI 8.5 framework.
# unica/patches/stock_blobs replaces /system/saiv with the S10+ (Android 12) one,
# but floating_feature keeps the S23 FE values (FACE_CLUSTER SR_V7, IMAGE_TAGGER
# V1101, STRIDE_OCR V2, AI_DEWARPING...). Gallery then loads old models with new
# libs and dies while viewing photos (face/OCR/tagger/crop run on view).
# Port of UN1CA sixteen unica/patches/saiv: target saiv as base, every Gallery
# feature whose version comes from the source gets the source models back.

CREW_SRC_FW="$FW_DIR/${SOURCE_FIRMWARE_PATH:-SM-S721B_EUX}"
if [ ! -d "$CREW_SRC_FW/system/system/saiv" ]; then
    LOGW "S721B source firmware saiv not found, Gallery models left as is"
    return 0
fi
CREW_HAS_VENDOR=false
[ -d "$CREW_SRC_FW/vendor/saiv" ] || [ -d "$CREW_SRC_FW/vendor/etc/saiv" ] && CREW_HAS_VENDOR=true
CREW_SNAP="u:object_r:vendor_configs_file:s0"
if grep -qs 'vendor_snap_file' "$WORK_DIR/vendor/etc/selinux/vendor_file_contexts"; then
    CREW_SNAP="u:object_r:vendor_snap_file:s0"
fi

# CREW_SRC <partition> <path> <uid> <gid> <mode> <label>: replace with the source copy
CREW_SRC()
{
    local SRC_PATH
    if [[ "$1" == "system" ]]; then SRC_PATH="$CREW_SRC_FW/system/$2"; else SRC_PATH="$CREW_SRC_FW/$1/$2"; fi
    if [ ! -e "$SRC_PATH" ]; then
        LOG "  - source has no /$1/${2#system/}, skipped"
        return 0
    fi
    CREW_DEL "$1" "$2"
    ADD_TO_WORK_DIR "$CREW_SRC_FW" "$1" "$2" "$3" "$4" "$5" "$6"
}
CREW_DEL()
{
    local W="$WORK_DIR/$1/$2"
    if [ -e "$W" ] || [ -L "$W" ]; then
        DELETE_FROM_WORK_DIR "$1" "$2"
    fi
}
CREW_FF() { grep -o "<$1>[^<]*" "$WORK_DIR/system/system/etc/floating_feature.xml" 2> /dev/null | cut -d '>' -f 2 || true; }

LOG_STEP_IN "- Matching saiv models to the One UI 8.5 Gallery (source: ${CREW_SRC_FW##*/}, vendor models: $CREW_HAS_VENDOR)"

# GALLERY_CONFIG_FACE_CLUSTER_VERSION
if [ -n "$(CREW_FF SEC_FLOATING_FEATURE_GALLERY_CONFIG_FACE_CLUSTER_VERSION)" ]; then
    CREW_SRC "system" "system/saiv/face/cluster_pb" 0 0 755 "u:object_r:system_file:s0"
fi

# GALLERY_CONFIG_IMAGE_TAGGER_VERSION
if [ -n "$(CREW_FF SEC_FLOATING_FEATURE_GALLERY_CONFIG_IMAGE_TAGGER_VERSION)" ]; then
    CREW_SRC "system" "system/saiv/image_understanding/db/aig" 0 0 755 "u:object_r:system_file:s0"
    if $CREW_HAS_VENDOR; then
        CREW_SRC "vendor" "saiv/image_understanding/db/aig_classifier" 0 2000 755 "$CREW_SNAP"
        CREW_DEL "vendor" "saiv/image_understanding/db/aig_detector"
        CREW_SRC "vendor" "saiv/image_understanding/db/aig_document_classifier" 0 2000 755 "$CREW_SNAP"
        CREW_SRC "vendor" "saiv/image_understanding/db/aig_document_detector" 0 2000 755 "$CREW_SNAP"
        CREW_DEL "vendor" "saiv/image_understanding/db/srr_interaction"
    fi
fi

# Photo Editor full/AI flavor segmenter
if $CREW_HAS_VENDOR; then
    if [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_Full/PhotoEditor_Full.apk" ] || \
            [ -f "$WORK_DIR/system/system/priv-app/PhotoEditor_AIFull/PhotoEditor_AIFull.apk" ]; then
        CREW_SRC "vendor" "etc/saiv/image_understanding/db/hs_segmenter" 0 0 755 "u:object_r:vendor_configs_file:s0"
    else
        CREW_DEL "vendor" "etc/saiv/image_understanding/db/hs_segmenter"
    fi
fi

# GALLERY_CONFIG_PET_CLUSTER_VERSION
CREW_PET="$(CREW_FF SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION)"
if [ -n "$CREW_PET" ] && [[ "$CREW_PET" != "None" ]]; then
    if $CREW_HAS_VENDOR; then
        CREW_SRC "vendor" "saiv/image_understanding/db/pet_detector" 0 2000 755 "$CREW_SNAP"
        CREW_SRC "vendor" "saiv/image_understanding/db/pet_mypetsearch" 0 2000 755 "$CREW_SNAP"
    fi
else
    CREW_DEL "vendor" "saiv/image_understanding/db/pet_detector"
    CREW_DEL "vendor" "saiv/image_understanding/db/pet_mypetsearch"
fi

# VISION_CONFIG_BIXBYVISION_VERSION (slens): only with Bixby Vision 3.5
if [ -f "$WORK_DIR/system/system/priv-app/BixbyVisionFramework3.5/BixbyVisionFramework3.5.apk" ]; then
    CREW_SRC "system" "system/saiv/image_understanding/db/slens_classifier" 0 0 755 "u:object_r:system_file:s0"
    CREW_SRC "system" "system/saiv/image_understanding/db/slens_detector" 0 0 755 "u:object_r:system_file:s0"
    if $CREW_HAS_VENDOR; then
        CREW_SRC "vendor" "etc/saiv/image_understanding/db/slens_classifier" 0 0 755 "u:object_r:vendor_configs_file:s0"
        CREW_SRC "vendor" "etc/saiv/image_understanding/db/slens_detector" 0 0 755 "u:object_r:vendor_configs_file:s0"
        CREW_DEL "vendor" "saiv/image_understanding/db/slens_classifier"
        CREW_DEL "vendor" "saiv/image_understanding/db/slens_detector"
    fi
else
    for CREW_P in system/saiv/image_understanding/db/slens_classifier system/saiv/image_understanding/db/slens_detector; do
        CREW_DEL "system" "$CREW_P"
    done
    for CREW_P in etc/saiv/image_understanding/db/slens_classifier etc/saiv/image_understanding/db/slens_detector \
            saiv/image_understanding/db/slens_classifier saiv/image_understanding/db/slens_detector; do
        CREW_DEL "vendor" "$CREW_P"
    done
fi

# CAMERA_DOCUMENTSCAN_SOLUTIONS (AI dewarping)
if [[ "$(CREW_FF SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS)" == *"AI_DEWARPING"* ]]; then
    CREW_SRC "system" "system/saiv/image_understanding/db/smartscan_rectifier" 0 0 755 "u:object_r:system_file:s0"
    $CREW_HAS_VENDOR && CREW_SRC "vendor" "saiv/image_understanding/db/smartscan_rectifier" 0 2000 755 "$CREW_SNAP"
else
    CREW_DEL "system" "system/saiv/image_understanding/db/smartscan_rectifier"
    CREW_DEL "vendor" "saiv/image_understanding/db/smartscan_rectifier"
fi

# VISION_CONFIG_SMART_CROPPING_SOLUTION
CREW_SRC "system" "system/saiv/smartcropping_2.0" 0 0 755 "u:object_r:system_file:s0"
$CREW_HAS_VENDOR && CREW_SRC "vendor" "saiv/image_understanding/db/sce_detector" 0 2000 755 "$CREW_SNAP"

# CAMERA_CONFIG_STRIDE_OCR_VERSION (Gallery text extraction)
CREW_SRC "system" "system/saiv/textrecognition" 0 0 755 "u:object_r:system_file:s0"

# Smart Scan segmenter
if $CREW_HAS_VENDOR && [ -f "$WORK_DIR/system/system/lib64/libSmartScan.camera.samsung.so" ]; then
    CREW_SRC "vendor" "etc/saiv/image_understanding/db/SS_segmenter" 0 2000 755 "u:object_r:vendor_configs_file:s0"
fi

LOG_STEP_OUT
unset CREW_SRC_FW CREW_HAS_VENDOR CREW_SNAP CREW_PET CREW_P
unset -f CREW_SRC CREW_DEL CREW_FF
