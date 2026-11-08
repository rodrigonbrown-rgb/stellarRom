# The source partitions identify as the S24 FE (r12s / SM-S721B) and /product
# wins ro.product.* resolution. Rewrite every existing name/model/device/
# marketname prop to the stock S10+ identity. KEEP_SOURCE_PRODUCT_PROPS=true skips.
if [[ "${KEEP_SOURCE_PRODUCT_PROPS:-false}" == "true" ]]; then
    LOG "- KEEP_SOURCE_PRODUCT_PROPS=true, keeping the source product identity"
    return 0
fi

PP_MODEL="$(GET_PROP "vendor" "ro.product.vendor.model")"
PP_NAME="$(GET_PROP "vendor" "ro.product.vendor.name")"
PP_DEVICE="$(GET_PROP "vendor" "ro.product.vendor.device")"
[ -n "$PP_MODEL" ] || PP_MODEL="SM-G975F"
[ -n "$PP_NAME" ] || PP_NAME="beyond2ltexx"
[ -n "$PP_DEVICE" ] || PP_DEVICE="beyond2"
if [[ "$PP_DEVICE" != "beyond2"* ]]; then
    ABORT "Target vendor reports ro.product.vendor.device=$PP_DEVICE, expected beyond2*"
fi

for PP_PART in system system_ext product odm; do
    for PP_KEY in model name device marketname; do
        PP_PROP="ro.product.$PP_PART.$PP_KEY"
        [ -n "$(GET_PROP "$PP_PART" "$PP_PROP")" ] || continue
        case "$PP_KEY" in
            model) PP_VALUE="$PP_MODEL" ;;
            name) PP_VALUE="$PP_NAME" ;;
            device) PP_VALUE="$PP_DEVICE" ;;
            marketname) PP_VALUE="Galaxy S10+" ;;
        esac
        SET_PROP "$PP_PART" "$PP_PROP" "$PP_VALUE"
    done
done
if [ -n "$(GET_PROP "system" "ro.build.product")" ]; then
    SET_PROP "system" "ro.build.product" "$PP_DEVICE"
fi
unset PP_MODEL PP_NAME PP_DEVICE PP_PART PP_KEY PP_PROP PP_VALUE
