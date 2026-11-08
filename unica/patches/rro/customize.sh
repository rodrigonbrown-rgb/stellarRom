RRO_SRC="${SOURCE_CODENAME}xxx"
if [[ -d "$SRC_DIR/target/$TARGET_CODENAME/overlay" ]]; then
    DECODE_APK "product" "overlay/framework-res__${RRO_SRC}__auto_generated_rro_product.apk"

    LOG "- Applying stock overlay configs"
    rm -rf "$APKTOOL_DIR/product/overlay/framework-res__${RRO_SRC}__auto_generated_rro_product.apk/res"
    cp -a --preserve=all \
        "$SRC_DIR/target/$TARGET_CODENAME/overlay" \
        "$APKTOOL_DIR/product/overlay/framework-res__${RRO_SRC}__auto_generated_rro_product.apk/res"
fi

# Source-agnostic: S24 FE and S23 FE SystemUI RROs carry different files.
if [ -f "$WORK_DIR/product/overlay/SystemUI__${RRO_SRC}__auto_generated_rro_product.apk" ]; then
    DECODE_APK "product" "overlay/SystemUI__${RRO_SRC}__auto_generated_rro_product.apk"
    SUI_RES="$APKTOOL_DIR/product/overlay/SystemUI__${RRO_SRC}__auto_generated_rro_product.apk/res"
    [ -f "$SUI_RES/values/bools.xml" ] && \
        sed -i -e "/config_enableDisplayCutoutProtection/d" -e "/config_enableRoundedCorner/d" "$SUI_RES/values/bools.xml"
    for f in values/dimens.xml values/public.xml drawable/rounded.xml; do
        if [ -f "$SUI_RES/$f" ]; then
            LOG "- Removing SystemUI RRO $f"
            rm -f "$SUI_RES/$f"
        fi
    done
    unset SUI_RES f
else
    LOGW "No SystemUI__${RRO_SRC}__ RRO in source, skipping"
fi
unset RRO_SRC
