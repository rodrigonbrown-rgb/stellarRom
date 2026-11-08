# beyond2lte debloat: third-party stubs, ads/promo, telemetry, factory tests and
# features the S10+ cannot use. Google Mobile Services, Play Store, Samsung
# account/cloud, Knox core, Secure Folder, Bixby, Link to Windows, Wearable,
# DeX, Smart View, Themes, Good Lock deps and all core apps are kept.

# Keep Software update in Settings (FOTA client + security policy agent).
SYSTEM_DEBLOAT="$(grep -v -E '^[[:space:]]*system/(priv-app/(FotaAgent|SOAgent[0-9]*)|etc/permissions/privapp-permissions-com\.(wssyncmldm|sec\.android\.soagent)\.xml)[[:space:]]*$' <<< "$SYSTEM_DEBLOAT")"

# Third-party stubs / promo
SYSTEM_DEBLOAT+="
system/app/Netflix_activationCommon
system/app/Netflix_stub
system/app/LinkedIn_SamsungStub
system/app/MSSkype_stub
system/app/Spotify
system/app/SpotifyStub
system/app/AmazonShopping
system/app/Booking
system/app/TikTok_stub
system/priv-app/MSOfficeHub_stub
system/priv-app/Microsoft365_stub
system/preload/Netflix_stub_preload
system/app/SamsungTVPlus
system/priv-app/SamsungTVPlus
system/priv-app/MinusOnePage
system/priv-app/SamsungFree
system/app/Upday
system/app/SamsungGlobalGoals
system/priv-app/SamsungGlobalGoals
system/app/GlobalGoals
system/priv-app/Tips
system/app/Tips
system/priv-app/SamsungMembers
system/app/SamsungMembers
system/priv-app/MateAgent
"

# AR / Kids / Wallet (Knox is tripped, Wallet cannot pay)
SYSTEM_DEBLOAT+="
system/priv-app/ARZone
system/app/ARZone
system/priv-app/ArZone
system/app/ARDrawing
system/priv-app/KidsHome
system/app/KidsHome
system/priv-app/SamsungWallet
system/priv-app/SamsungPay
system/app/SamsungPayStub
system/priv-app/SamsungPayStub
"

# Telemetry / diagnostics / factory test
SYSTEM_DEBLOAT+="
system/priv-app/DeviceQualityAgent
system/priv-app/DeviceQualityAgent36
system/priv-app/SEMFactoryApp
system/app/FactoryCameraFB
system/app/FactoryAirCommandManager
system/app/WlanTest
system/app/SilentLog
system/priv-app/AutomationTest_FB
system/app/AutomationTest_FB
system/app/SmartReminder
"


# Perf: background Samsung services (AI content capture/suggestions, personalization
# telemetry, silent preload app updater, manual, avatar picker). Folder names vary
# per firmware, so match what the source actually ships.
for PB in "$WORK_DIR"/system/system/priv-app/{SmartSuggestions*,SamsungSmartSuggestions*,Rubin*,AppUpdateCenter*,AvatarPicker*} \
          "$WORK_DIR"/system/system/app/{WebManual*,SmartSuggestions*}; do
    [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
done
unset PB
# Optional, games only: Samsung GOS throttles games; uncomment to remove it.
# SYSTEM_DEBLOAT+=$'\n'"system/priv-app/GameOptimizingService"

# Round 2: extra Samsung services (stickers/AR extras, blockchain, Hiya caller ID,
# background resource updater, photo screensaver, McAfee device protection).
# Only folders that exist in the source are removed.
for PB in "$WORK_DIR"/system/system/priv-app/{StickerCenter*,LiveStickers*,AvatarEmojiSticker*,PrivateShare*,ColdWalletService*,BlockchainBasicKit*,SmartCallProvider*,HiyaService*,GalaxyResourceUpdater*,*DeviceSecurity*} \
          "$WORK_DIR"/system/system/app/{StickerCenter*,LiveStickers*,AvatarEmojiSticker*,PhotoTable*,SmartCallProvider*,HiyaService*,GalaxyResourceUpdater*}; do
    [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
done
unset PB
