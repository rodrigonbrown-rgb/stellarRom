# crew: Power+Vol Down screenshot on the One UI 8.5 (S23 FE) framework.
# KeyGestureController$LocalKeyGestureEventHandler only takes the chord screenshot
# (gesture 0xb) when InputRune.PWM_KEY_COMBINATION_SCREENSHOT_SIDE_KEY is true, and
# InputRune reads it from SETTINGS_SUPPORT_FUNCTION_KEY_MENU. There is no legacy
# path left, so keep InputRune stock and enable the side-key config like the S23 FE.
LOG_STEP_IN "- Screenshot key combination: side-key config (FUNCTION_KEY_MENU=TRUE)"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_FUNCTION_KEY_MENU" "TRUE"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BIXBY_SUPPORT_LONG_KEY_SERVICE" "FALSE"
LOG_STEP_OUT
