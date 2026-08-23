using Toybox.Application;
using Toybox.Lang;

// Cached access to the Connect IQ properties defined in resources/properties.xml.
//
// Watch faces run onUpdate every second, so every read goes through a module-level
// cache that is filled once and only invalidated from App.onSettingsChanged. Each
// read is guarded: a missing or malformed property degrades to the documented
// default instead of throwing on-watch.
module Settings {

    // --- Background ---
    const BG_STARFIELD    = 0;
    const BG_ZODIAC_STARS = 1;
    const BG_ZODIAC_LINES = 2;

    // --- Comet trail ---
    const COMET_CLASSIC        = 0;
    const COMET_SPECTRUM_TRAIL = 1;
    const COMET_SPECTRUM_RING  = 2;

    // --- Hour mark style ---
    const HOUR_MARK_NUMERALS       = 0;
    const HOUR_MARK_LINES          = 1;
    const HOUR_MARK_LINES_CARDINAL = 2;

    // --- Hand colour ---
    // 0-7 are the fixed presets in Theme.handPreset; 8 has no fixed value and
    // is resolved per frame against the second hand's hue.
    const HAND_COLOR_SPECTRUM = 8;

    // --- Eclipse visibility gate ---
    const ECLIPSE_ALWAYS  = 0;
    const ECLIPSE_IF_HERE = 1;

    // --- Debug eclipse override ---
    const DEBUG_ECLIPSE_OFF   = 0;
    const DEBUG_ECLIPSE_LUNAR = 1;
    const DEBUG_ECLIPSE_SOLAR = 2;

    // Sentinel for "no debug coordinate set" (valid lat/lon never reach 999).
    const COORD_UNSET = 999.0;

    var _loaded = false;

    const ECLIPSE_SRC_TABLE   = 0;
    const ECLIPSE_SRC_COMPUTE = 1;

    var cometMode;
    var cometOnFiveSec;
    var showOrbitRing;
    var showHourNumerals;
    var hourNumeralsOuter;
    var hourMarkStyle;
    var showSecondNumerals;
    var handColor;
    var handHollow;
    var starCount;
    var background;
    var zodiacSign;
    var enableRainbowWave;
    var waveHour;
    var waveIntervalHours;
    var waveTestMode;
    var eclipseEffects;
    var eclipseVisibility;
    var eclipseSource;
    var debugEclipse;
    var debugTimeOffsetDays;
    var debugLatitude;
    var debugLongitude;

    // Called from App.onSettingsChanged so the next draw picks up new values.
    function invalidate() {
        _loaded = false;
    }

    function load() {
        if (_loaded) { return; }

        cometMode           = numberOr("CometMode", 0, 0, 2);
        cometOnFiveSec      = boolOr("CometOnFiveSec", false);
        showOrbitRing       = boolOr("ShowOrbitRing", false);
        showHourNumerals    = boolOr("ShowHourNumerals", true);
        hourNumeralsOuter   = boolOr("HourNumeralsOuter", false);
        hourMarkStyle       = numberOr("HourMarkStyle", 0, 0, 2);
        showSecondNumerals  = boolOr("ShowSecondNumerals", true);
        handColor           = numberOr("HandColor", HAND_COLOR_SPECTRUM, 0, 8);
        handHollow          = numberOr("HandHollow", 0, 0, 80);
        starCount           = numberOr("StarCount", 120, 0, 200);
        background          = numberOr("Background", 0, 0, 2);
        zodiacSign          = numberOr("ZodiacSign", 0, 0, 12);
        enableRainbowWave   = boolOr("EnableRainbowWave", true);
        waveHour            = numberOr("WaveHour", 0, 0, 23);
        waveIntervalHours   = numberOr("WaveIntervalHours", 3, 1, 24);
        waveTestMode        = boolOr("WaveTestMode", false);
        eclipseEffects      = boolOr("EclipseEffects", true);
        eclipseVisibility   = numberOr("EclipseVisibility", 0, 0, 1);
        eclipseSource       = numberOr("EclipseSource", 0, 0, 1);
        debugEclipse        = numberOr("DebugEclipse", 0, 0, 2);
        debugTimeOffsetDays = floatOr("DebugTimeOffsetDays", 0.0);
        debugLatitude       = floatOr("DebugLatitude", COORD_UNSET);
        debugLongitude      = floatOr("DebugLongitude", COORD_UNSET);

        _loaded = true;
    }

    // --- Guarded readers ----------------------------------------------------

    (:typecheck(false))
    function raw(key) {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    (:typecheck(false))
    function write(key, value) {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
            // Storage full or key undeclared: a diagnostic readout is never
            // worth taking the face down for.
        }
    }

    (:typecheck(false))
    function numberOr(key, fallback, lo, hi) {
        var v = raw(key);
        if (v == null) { return fallback; }
        var n;
        try {
            n = v.toNumber();
        } catch (e) {
            return fallback;
        }
        if (n == null || n < lo || n > hi) { return fallback; }
        return n;
    }

    (:typecheck(false))
    function boolOr(key, fallback) {
        var v = raw(key);
        if (v == null) { return fallback; }
        if (v instanceof Lang.Boolean) { return v; }
        if (v instanceof Lang.Number) { return v != 0; }
        return fallback;
    }

    (:typecheck(false))
    function floatOr(key, fallback) {
        var v = raw(key);
        if (v == null) { return fallback; }
        var f;
        try {
            f = v.toFloat();
        } catch (e) {
            return fallback;
        }
        if (f == null) { return fallback; }
        return f;
    }
}
