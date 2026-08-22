using Toybox.Time;
using Toybox.Math;

// Lunar phase from the mean synodic month, plus eclipse detection.
//
// Phase is accurate to a few hours, which is far finer than a watch face can
// display. Eclipses are looked up in the exact NASA-derived table in
// EclipseData.mc first; the mean-element node math here is only the fallback
// for dates outside that table's span. No UI dependencies.
module MoonPhase {
    const SYNODIC        = 29.530588853d;   // mean synodic month, days
    const DRACONIC       = 27.212220817d;   // node-to-node month, days
    const REF_NEW_MOON   = 2451550.1d;      // JD of new moon 2000-01-06 18:14 UTC
    const UNIX_EPOCH_JD  = 2440587.5d;      // JD at unix epoch
    const DAYS_1970_2000 = 10957.0d;        // days from the unix epoch to 2000-01-01

    // Reference epoch for the lunation number k used by the eclipse algorithm:
    // k = 0 is the new moon of 2000 January 6.
    const K_EPOCH_JD  = 2451550.09766d;
    const K_PER_MONTH = 29.530588861d;

    // How far either side of greatest eclipse the face shows the effect.
    const WINDOW_DAYS = 0.25;              // +/- 6 hours

    // Phase fraction 0..1 for a unix epoch time in seconds.
    // 0.0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    function fractionAt(epochSeconds) {
        var jd  = epochSeconds / 86400.0d + UNIX_EPOCH_JD;
        var age = fmod(jd - REF_NEW_MOON, SYNODIC);
        if (age < 0.0) { age += SYNODIC; }
        return age / SYNODIC;
    }

    function fraction() {
        return fractionAt(Time.now().value());
    }

    // Illuminated fraction of the disc, 0..1.
    function illumination(frac) {
        return (1.0 - Math.cos(2.0 * Math.PI * frac)) / 2.0;
    }

    // Nearest of the 8 named phases, 0..7.
    function phaseIndex(frac) {
        var idx = Math.floor(frac * 8.0 + 0.5).toNumber();
        return idx % 8;
    }

    function phaseName(frac) {
        var names = [
            "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
            "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"
        ];
        return names[phaseIndex(frac)];
    }

    // Days since 2000-01-01 00:00 UTC, fractional.
    //
    // All eclipse arithmetic runs in this unit rather than raw epoch seconds:
    // Monkey C's Number is 32-bit, so epoch-second arithmetic starts
    // overflowing in 2038 while the table runs to 2045.
    function days2000(epochSeconds) {
        return epochSeconds / 86400.0d - DAYS_1970_2000;
    }

    // --- Eclipse detection --------------------------------------------------

    // Returns null, or a dictionary:
    //   :type      EclipseData type code
    //   :lunar     true for a lunar eclipse, false for solar
    //   :magnitude Float
    //   :offset    days since greatest eclipse (negative = still to come)
    //   :exact     true when it came from the table, false when computed
    //
    // The table is authoritative inside its span: a timestamp that falls in
    // 2025..2045 with no table hit genuinely has no eclipse, so the estimating
    // path is never consulted there.
    // Eclipse state changes over hours while onUpdate runs every second, so the
    // answer is cached and only recomputed when the minute rolls over.
    var _cacheMinute = null;
    var _cacheResult = null;

    (:typecheck(false))
    function eclipseAt(epochSeconds) {
        var minute = (epochSeconds / 60).toNumber();
        if (_cacheMinute != null && _cacheMinute == minute) {
            return _cacheResult;
        }
        _cacheMinute = minute;
        _cacheResult = computeEclipseAt(epochSeconds);
        return _cacheResult;
    }

    // Force the next eclipseAt to recompute (used when settings change).
    function invalidateCache() {
        _cacheMinute = null;
        _cacheResult = null;
    }

    // Tell the settings screen which source is in play, so the 2045 horizon is
    // visible without digging. Only written when the wording actually changes.
    var _lastSourceText = null;

    (:typecheck(false))
    function reportDataSource(epochSeconds) {
        var text;
        if (Settings.eclipseSource == Settings.ECLIPSE_SRC_COMPUTE) {
            text = "calculated - exact data available to " + EclipseData.LAST_LABEL;
        } else if (haveExactData(epochSeconds)) {
            text = "exact, through " + EclipseData.LAST_LABEL;
        } else {
            text = "estimated, beyond " + EclipseData.LAST_LABEL;
        }
        if (_lastSourceText != null && _lastSourceText.equals(text)) { return; }
        _lastSourceText = text;
        Settings.write("EclipseDataInfo", text);
    }

    (:typecheck(false))
    function computeEclipseAt(epochSeconds) {
        reportDataSource(epochSeconds);
        var d = days2000(epochSeconds);

        // "Always calculate" makes the computed path testable against the table
        // on dates the table already covers.
        if (Settings.eclipseSource == Settings.ECLIPSE_SRC_COMPUTE) {
            return estimateAt(d);
        }

        var hit = lookup(d);
        if (hit != null) { return hit; }

        if (d >= EclipseData.FIRST_DAY - 1.0 && d <= EclipseData.LAST_DAY + 1.0) {
            return null;
        }
        return estimateAt(d);
    }

    // True while the timestamp is covered by the exact table.
    function haveExactData(epochSeconds) {
        var d = days2000(epochSeconds);
        return d >= EclipseData.FIRST_DAY - 1.0 && d <= EclipseData.LAST_DAY + 1.0;
    }

    // Binary-search the table for an event whose maximum is within the window.
    (:typecheck(false))
    function lookup(d) {
        var days = EclipseData.DAYS;
        var n = days.size();
        var target = Math.floor(d).toNumber() - 1;

        // First index with days[i] >= target.
        var lo = 0;
        var hi = n;
        while (lo < hi) {
            var mid = (lo + hi) / 2;
            if (days[mid] < target) { lo = mid + 1; } else { hi = mid; }
        }

        // An event's window can reach into the next day, so check a few entries.
        for (var i = lo; i < n && days[i] <= target + 2; i += 1) {
            var maxDay = days[i] + EclipseData.MINUTES[i] / 1440.0;
            var offset = d - maxDay;
            if (offset >= -WINDOW_DAYS && offset <= WINDOW_DAYS) {
                var tm = EclipseData.TYPEMAG[i];
                var type = tm / 1000;
                return {
                    :type      => type,
                    :lunar     => EclipseData.isLunar(type),
                    :magnitude => (tm % 1000) / 100.0,
                    :offset    => offset,
                    :exact     => true
                };
            }
        }
        return null;
    }

    // Computed eclipse detection, used outside the table's span.
    //
    // Meeus, Astronomical Algorithms 2nd ed., chapters 49 and 54. Validated
    // against all 93 events in the table by tools\check-eclipse-math.ps1:
    // 92 detected (the miss is a very shallow penumbral, which is not rendered
    // anyway), maximum timing error 1.1 minutes, and no false positives across
    // 14945 samples spanning 2025-2045.
    //
    // A candidate eclipse exists only at syzygy, so rather than scanning time
    // this evaluates the handful of lunations bracketing the instant: integer
    // k is a new moon (solar), k + 0.5 is a full moon (lunar).
    (:typecheck(false))
    function estimateAt(d) {
        var jd = d + 2451544.5d;
        var kApprox = (jd - K_EPOCH_JD) / K_PER_MONTH;
        var base = Math.floor(kApprox);

        for (var i = -1; i <= 1; i += 1) {
            for (var half = 0; half < 2; half += 1) {
                var k = (base + i + half * 0.5d).toDouble();
                var e = eclipseForK(k);
                if (e == null) { continue; }
                var offset = (jd - e[:jde]);
                if (offset >= -WINDOW_DAYS && offset <= WINDOW_DAYS) {
                    e[:offset] = offset;
                    return e;
                }
            }
        }
        return null;
    }

    // Meeus chapter 54, for one lunation number. Returns null when that syzygy
    // produces no eclipse.
    (:typecheck(false))
    function eclipseForK(k) {
        var t  = k / 1236.85d;
        var t2 = t * t;
        var t3 = t2 * t;
        var t4 = t3 * t;

        // Argument of latitude: the Moon's distance from a node. Outside this
        // band no eclipse of either kind is geometrically possible, and this is
        // the cheap test that rejects the great majority of lunations.
        var f = 160.7108d + 390.67050284d * k - 0.0016118d * t2
              - 0.00000227d * t3 + 0.000000011d * t4;
        if (absf(sinDeg(f)) > 0.36) { return null; }

        var m  = 2.5534d + 29.10535670d * k - 0.0000014d * t2 - 0.00000011d * t3;
        var mp = 201.5643d + 385.81693528d * k + 0.0107582d * t2
               + 0.00001238d * t3 - 0.000000058d * t4;
        var om = 124.7746d - 1.56375588d * k + 0.0020672d * t2 + 0.00000215d * t3;
        var ec = 1.0 - 0.002516 * t - 0.0000074 * t2;

        var f1 = f - 0.02665d * sinDeg(om);
        var a1 = 299.77d + 0.107408d * k - 0.009173d * t2;

        var solar = (k - Math.floor(k)) < 0.01;

        var jde = K_EPOCH_JD + K_PER_MONTH * k + 0.00015437d * t2
                - 0.000000150d * t3 + 0.00000000073d * t4;

        jde += (solar ? -0.4075 : -0.4065) * sinDeg(mp);
        jde += (solar ?  0.1721 :  0.1727) * ec * sinDeg(m);
        jde += 0.0161 * sinDeg(2 * mp) - 0.0097 * sinDeg(2 * f1);
        jde += 0.0073 * ec * sinDeg(mp - m) - 0.0050 * ec * sinDeg(mp + m);
        jde += -0.0023 * sinDeg(mp - 2 * f1) + 0.0021 * ec * sinDeg(2 * m);
        jde += 0.0012 * sinDeg(mp + 2 * f1) + 0.0006 * ec * sinDeg(2 * mp + m);
        jde += -0.0004 * sinDeg(3 * mp) - 0.0003 * ec * sinDeg(m + 2 * f1);
        jde += 0.0003 * sinDeg(a1) - 0.0002 * ec * sinDeg(m - 2 * f1);
        jde += -0.0002 * ec * sinDeg(2 * mp - m) - 0.0002 * sinDeg(om);

        var p = 0.2070 * ec * sinDeg(m) + 0.0024 * ec * sinDeg(2 * m)
              - 0.0392 * sinDeg(mp) + 0.0116 * sinDeg(2 * mp)
              - 0.0073 * ec * sinDeg(mp + m) + 0.0067 * ec * sinDeg(mp - m)
              + 0.0118 * sinDeg(2 * f1);

        var q = 5.2207 - 0.0048 * ec * cosDeg(m) + 0.0020 * ec * cosDeg(2 * m)
              - 0.3299 * cosDeg(mp) - 0.0060 * ec * cosDeg(mp + m)
              + 0.0041 * ec * cosDeg(mp - m);

        var w = absf(cosDeg(f1));
        // Least distance from the axis of the shadow to Earth's centre, in
        // Earth radii, and the radius of the umbral cone there.
        var gamma = (p * cosDeg(f1) + q * sinDeg(f1)) * (1.0 - 0.0048 * w);
        var u = 0.0059 + 0.0046 * ec * cosDeg(m) - 0.0182 * cosDeg(mp)
              + 0.0004 * cosDeg(2 * mp) - 0.0005 * cosDeg(m + mp);
        var ag = absf(gamma);

        if (solar) {
            if (ag > 1.5433 + u) { return null; }
            var stype = EclipseData.PARTIAL_SOLAR;
            var smag = (1.5433 + u - ag) / (0.5461 + 2.0 * u);
            if (ag < 0.9972) {
                if (u < 0.0)          { stype = EclipseData.TOTAL_SOLAR; }
                else if (u > 0.0047)  { stype = EclipseData.ANNULAR; }
                else                  { stype = EclipseData.HYBRID; }
                // Meeus gives magnitude directly only for partial eclipses; a
                // central eclipse is at or above unity by definition, and the
                // renderer keys off the type anyway.
                smag = 1.0;
            }
            return { :type => stype, :lunar => false, :magnitude => smag,
                     :jde => jde, :offset => 0.0, :exact => false };
        }

        var umbral = (1.0128 - u - ag) / 0.5450;
        var penumbral = (1.5573 + u - ag) / 0.5450;
        if (penumbral <= 0.0) { return null; }

        var ltype = EclipseData.PENUMBRAL;
        if (umbral >= 1.0)     { ltype = EclipseData.TOTAL_LUNAR; }
        else if (umbral > 0.0) { ltype = EclipseData.PARTIAL_LUNAR; }

        return { :type => ltype, :lunar => true, :magnitude => umbral,
                 :jde => jde, :offset => 0.0, :exact => false };
    }

    // Angles here run to hundreds of thousands of degrees (385.8 deg per
    // lunation, times a k in the hundreds), so they are folded into 0..360
    // before the conversion: Math.sin of a huge argument throws away exactly
    // the low-order precision this algorithm depends on.
    function sinDeg(d) {
        return Math.sin(deg360(d) * Math.PI / 180.0d);
    }

    function cosDeg(d) {
        return Math.cos(deg360(d) * Math.PI / 180.0d);
    }

    function deg360(d) {
        return d - 360.0d * Math.floor(d / 360.0d);
    }

    function absf(v) {
        return (v < 0.0) ? -v : v;
    }

    // Floating-point modulo (Math has no fmod in this API).
    function fmod(a, b) {
        return a - b * Math.floor(a / b);
    }
}
