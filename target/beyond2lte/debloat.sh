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

# Round 3 (crew perf): telemetry/security-report agents, promo, factory/test tools.
# Only folders that exist in the source are removed.
for PB in "$WORK_DIR"/system/system/priv-app/{DsmsAPK*,SecurityLogAgent*,MyGalaxy*,SamsungRewards*,Rewards*,Cameralyzer*,HwModuleTest*,EpdgTest*,UwbTest*,SamsungDailyBoard*,DailyBoard*,LedCoverDream*,SmartFittingService*,SamsungCustomerService*,AppCloud*,AuraLauncher*,PhotoTable*} \
          "$WORK_DIR"/system/system/app/{DsmsAPK*,SecurityLogAgent*,MyGalaxy*,SamsungRewards*,Cameralyzer*,HwModuleTest*,EpdgTest*,UwbTest*,SamsungDailyBoard*,DailyBoard*,BasicDreams*,AppCloud*,AuraLauncher*}; do
    [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
done
unset PB

# Round 4 (crew, One UI 9): AR extras, promo/stub apps, Pay/Wallet (dead on
# tripped Knox). Google apps only with CREW_DB_GAPPS=true (all reinstallable from Play).
CREW_DB_GAPPS=false
CREW_DB="AREmoji* AREmojiEditor* AvatarEmojiSticker* ARZone* ARDrawing* LiveDrawing* Tips* SamsungMembers* Upday* MinusOnePage* SamsungFree* GlobalGoals* SamsungGlobalGoals* TVPlus* SamsungTVPlus* Netflix_stub* Netflix_activationCommon* LinkedIn_SamsungStub* MSSkype_stub* OfficeMobile_SamsungStub* Spotify* DictDiotekForSec* SmartTutor* Hmt* SamsungPay* SamsungWallet* SpayFw*"
$CREW_DB_GAPPS && CREW_DB+=" Duo* Meet* Videos* YouTube* YTMusic* Drive* Maps* Gmail2* Photos*"
for CREW_N in $CREW_DB; do
    for PB in "$WORK_DIR"/system/system/{app,priv-app,preload}/$CREW_N; do
        [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
    done
    for PB in "$WORK_DIR"/product/{app,priv-app,preload}/$CREW_N; do
        [ -e "$PB" ] && PRODUCT_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/product/}"
    done
done
unset CREW_DB CREW_DB_GAPPS CREW_N PB

# Round 5 (crew, One UI 9): factory/test tools, hardware the S10+ lacks
# (satellite), dead platforms (Gear VR), telemetry, Play-installable a11y apps.
for PB in "$WORK_DIR"/system/system/app/{FacAtFunction,HMT,GearManagerStub,EasterEgg,BlockchainBasicKit,VoiceAccess,LiveTranscribe} \
          "$WORK_DIR"/system/system/priv-app/{WarrantyCare,SatellitePointingUI,GpuWatchApp,DeviceQualityAgent38,SecFactoryPhoneTest,SmartEpdgTestApp}; do
    [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
done
unset PB

# Never debloat: thermal (SDHMS/SSRM/SIOP, GOS), Galaxy AI and its deps
# (AICore/intelligence, Now Brief = SmartSuggestions + Rubin, translation,
# interpreter, on-device language models, Bixby, keyboard/notes/handwriting,
# photo AI), Secure Folder. This also undoes earlier rounds that matched them.
CREW_KEEP='SamsungDeviceHealthManagerService|SDHMS|SSRM|Siop|GameOptimizingService|AICore|AiCore|Intelligence|SmartSuggestions|Rubin|Translat|Interpreter|LanguageModel|LLM|Bixby|Honeyboard|SamsungKeyboard|SamsungNotes|Handwriting|HwrService|PhotoRemaster|PhotoEditor|SmartCapture|ImageAI|AiWallpaper|Galaxy[Aa][Ii]|SecureFolder|KnoxCore|Routines'
SYSTEM_DEBLOAT="$(grep -v -E "$CREW_KEEP" <<< "$SYSTEM_DEBLOAT")"
PRODUCT_DEBLOAT="$(grep -v -E "$CREW_KEEP" <<< "${PRODUCT_DEBLOAT:-}")"
unset CREW_KEEP

# crew: ExtremeROM (sixteen) unica/debloat.sh parity - background agents and
# Meta/Microsoft installer stubs. Kept on purpose: FotaAgent/SOAgent (Software
# update), Bixby, YourPhone (Link to Windows), Samsung Pass.
for PB in "$WORK_DIR"/system/system/priv-app/{FBInstaller_NS*,FBServices*,OneDrive_Samsung*,AppUpdateCenter*,OMCAgent*,CpAgent*,SKMSAgent*,DiagMonAgent*,EnhancedAttestationAgent*,ImsLogger*,IpsGeofence*,OdaService*,StickerFaceARAvatar*,AREmoji*} \
          "$WORK_DIR"/system/system/app/{FBAppManager_NS*,KidsHome_Installer*,MAPSAgent*,PlayAutoInstallConfig*,ccinfo*,ChromeCustomizations*,MDMApp*,UniversalMDMClient*,Rampart*,SilentLog*,Traceur*,WifiGuider*} \
          "$WORK_DIR"/system/system/preload/{Facebook_stub_preload*,Instagram_stub_preload*}; do
    [ -e "$PB" ] && SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}"
done
SYSTEM_DEBLOAT+="
system/etc/permissions/privapp-permissions-com.microsoft.skydrive.xml
system/etc/permissions/privapp-permissions-com.samsung.android.app.updatecenter.xml
system/etc/permissions/privapp-permissions-meta.xml
system/etc/sysconfig/meta-hiddenapi-package-allowlist.xml
"
unset PB

# crew: Samsung TTS engine + every voice pack (Google speech services stays)
for PB in "$WORK_DIR"/system/system/{app,priv-app}/SamsungTTS* "$WORK_DIR"/product/{app,priv-app}/SamsungTTS*; do
    [ -e "$PB" ] || continue
    case "$PB" in
        "$WORK_DIR"/system/*) SYSTEM_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/system/}" ;;
        "$WORK_DIR"/product/*) PRODUCT_DEBLOAT+=$'\n'"${PB#"$WORK_DIR"/product/}" ;;
    esac
done
unset PB

# crew round 6: safe extras (SYSTEM_DEBLOAT)
SYSTEM_DEBLOAT+="
system/priv-app/Bixby
system/app/BixbyWakeup
system/app/VisionIntelligence3.7
system/priv-app/BeaconManager
system/priv-app/EasySetup
system/priv-app/SecureFolder
system/app/BBCAgent
system/priv-app/FaceService
system/priv-app/EarphoneTypeC
system/priv-app/EsimClient
system/app/SmartSwitchAgent
system/priv-app/SmartSwitchAssistant
system/priv-app/MCFDeviceSync
system/priv-app/YourPhone_P1_5
system/app/ParentalCare
system/app/VTCameraSetting
system/app/SketchBook
system/app/CocktailQuickTool
system/app/EasymodeContactsWidget81
system/system_ext/app/ModemLogging
system/priv-app/IAFDManagerService
system/app/SafetyInformation
system/system_ext/priv-app/GoogleFeedback
system/app/ARCore
"

# crew round 6: safe extras (PRODUCT_DEBLOAT)
PRODUCT_DEBLOAT+="
priv-app/GoogleRestore
app/GoogleLocationHistory
priv-app/HotwordEnrollmentXGoogleExCORTEXM4
priv-app/HotwordEnrollmentOKGoogleExCORTEXM4
"
