using Toybox.Position;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;

// Where the Sun is, and where the watch is.
//
// Used only by the optional eclipse visibility gate. Position comes from
// Position.getInfo(), which returns the *last known* fix and never powers up
// the GPS, so it is free to call from a watch face every second.
module SkyPosition {

    const J2000 = 2451545.0;
    const UNIX_EPOCH_JD = 2440587.5;

    // Sun altitudes are compared against this rather than 0 to allow for
    // refraction and the solar radius.
    const HORIZON = -0.5;

    // Throttle for the diagnostic property writes: properties live in flash and
    // onUpdate runs every second.
    const WRITE_MIN_SECONDS = 3600;
    const WRITE_MIN_DEGREES = 0.05;      // ~5 km

    var _lastWriteEpoch = null;
    var _lastLat = null;
    var _lastLon = null;

    // --- Position -----------------------------------------------------------

    // Returns [latDeg, lonDeg] or null. Debug overrides win so the gate can be
    // exercised in the simulator without depending on simulated position.
    (:typecheck(false))
    function currentPosition() {
        if (Settings.debugLatitude != Settings.COORD_UNSET
                && Settings.debugLongitude != Settings.COORD_UNSET) {
            return [Settings.debugLatitude, Settings.debugLongitude];
        }

        if (!(Toybox has :Position)) { return null; }

        var info = null;
        try {
            info = Position.getInfo();
        } catch (e) {
            return null;
        }
        if (info == null || info.position == null) { return null; }
        if ((info has :accuracy) && info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return null;
        }

        var deg = info.position.toDegrees();
        if (deg == null || deg.size() < 2) { return null; }
        if (deg[0] == 0.0 && deg[1] == 0.0) { return null; }   // never fixed yet
        return [deg[0], deg[1]];
    }

    // Human-readable accuracy bucket for the settings readout.
    (:typecheck(false))
    function accuracyLabel() {
        if (Settings.debugLatitude != Settings.COORD_UNSET
                && Settings.debugLongitude != Settings.COORD_UNSET) {
            return "debug override";
        }
        if (!(Toybox has :Position)) { return "unsupported"; }
        var info = null;
        try {
            info = Position.getInfo();
        } catch (e) {
            return "none";
        }
        if (info == null || !(info has :accuracy)) { return "unknown"; }
        if (info.accuracy == Position.QUALITY_GOOD)   { return "good"; }
        if (info.accuracy == Position.QUALITY_USABLE) { return "usable"; }
        if (info.accuracy == Position.QUALITY_POOR)   { return "poor"; }
        return "none";
    }

    // --- Solar position -----------------------------------------------------

    // Altitude of the Sun in degrees at a unix epoch time, for a given
    // latitude/longitude in degrees. Low-precision NOAA/Meeus formulation:
    // good to a fraction of a degree, far better than the horizon test needs.
    function sunAltitude(epochSeconds, latDeg, lonDeg) {
        var n = epochSeconds / 86400.0 + UNIX_EPOCH_JD - J2000;

        var meanLon = deg360(280.460 + 0.9856474 * n);
        var meanAnom = deg360(357.528 + 0.9856003 * n);
        var g = rad(meanAnom);

        // Apparent ecliptic longitude.
        var lambda = rad(deg360(meanLon + 1.915 * Math.sin(g) + 0.020 * Math.sin(2.0 * g)));
        var eps = rad(23.439 - 0.0000004 * n);

        var sinDec = Math.sin(eps) * Math.sin(lambda);
        var dec = Math.asin(sinDec);
        var ra = Math.atan2(Math.cos(eps) * Math.sin(lambda), Math.cos(lambda));

        // Greenwich mean sidereal time, then the local hour angle.
        var gmst = deg360(280.46061837 + 360.98564736629 * n);
        var hourAngle = rad(deg360(gmst + lonDeg - deg(ra)));

        var phi = rad(latDeg);
        var sinAlt = Math.sin(phi) * Math.sin(dec)
                   + Math.cos(phi) * Math.cos(dec) * Math.cos(hourAngle);
        if (sinAlt > 1.0)  { sinAlt = 1.0; }
        if (sinAlt < -1.0) { sinAlt = -1.0; }
        return deg(Math.asin(sinAlt));
    }

    // At a lunar eclipse the Moon is by definition opposite the Sun, so its
    // altitude is the Sun's negated to within a degree or two -- ample for
    // "is it above my horizon".
    function moonAltitudeAtOpposition(epochSeconds, latDeg, lonDeg) {
        return -sunAltitude(epochSeconds, latDeg, lonDeg);
    }

    // --- The gate -----------------------------------------------------------

    // Should an eclipse be shown at this place and time?
    //
    // Returns true whenever there is no position to judge with: never hide a
    // real eclipse just because the watch has not had a fix.
    (:typecheck(false))
    function eclipseVisible(eclipse, epochSeconds) {
        if (Settings.eclipseVisibility == Settings.ECLIPSE_ALWAYS) {
            recordNotUsed();
            return true;
        }

        var pos = currentPosition();
        if (pos == null) {
            recordNoFix();
            return true;
        }
        recordFix(pos[0], pos[1], epochSeconds);

        var alt = sunAltitude(epochSeconds, pos[0], pos[1]);
        if (eclipse[:lunar]) {
            // Moon up == Sun down.
            return -alt > HORIZON;
        }
        // Solar: the Sun being up is necessary but not sufficient -- the path of
        // totality is far narrower than this test. MoonDial dims the corona to
        // signal that.
        return alt > HORIZON;
    }

    // --- Diagnostic readout (settings screen only, never the dial) ----------

    function recordNotUsed() {
        writeInfo("position not used (showing all eclipses)");
    }

    function recordNoFix() {
        writeInfo("no position - showing all eclipses");
    }

    (:typecheck(false))
    function recordFix(lat, lon, epochSeconds) {
        if (!shouldWrite(lat, lon, epochSeconds)) { return; }

        _lastLat = lat;
        _lastLon = lon;
        _lastWriteEpoch = epochSeconds;

        Settings.write("LastFixLat", lat);
        Settings.write("LastFixLon", lon);
        writeInfo(fmt4(lat) + ", " + fmt4(lon) + " - " + stamp(epochSeconds)
            + " - " + accuracyLabel());
    }

    (:typecheck(false))
    function shouldWrite(lat, lon, epochSeconds) {
        if (_lastWriteEpoch == null) { return true; }
        if (epochSeconds - _lastWriteEpoch >= WRITE_MIN_SECONDS) { return true; }
        if (absf(lat - _lastLat) >= WRITE_MIN_DEGREES) { return true; }
        if (absf(lon - _lastLon) >= WRITE_MIN_DEGREES) { return true; }
        return false;
    }

    var _lastInfo = null;

    function writeInfo(text) {
        if (_lastInfo != null && _lastInfo.equals(text)) { return; }
        _lastInfo = text;
        Settings.write("LastFixInfo", text);
    }

    // --- Small helpers ------------------------------------------------------

    function stamp(epochSeconds) {
        var info = Gregorian.info(new Time.Moment(epochSeconds), Time.FORMAT_SHORT);
        return info.year.format("%04d") + "-" + info.month.format("%02d") + "-"
             + info.day.format("%02d") + " " + info.hour.format("%02d") + ":"
             + info.min.format("%02d");
    }

    function fmt4(v) {
        return v.format("%.4f");
    }

    function absf(v) {
        return (v < 0.0) ? -v : v;
    }

    function rad(d) {
        return d * Math.PI / 180.0;
    }

    function deg(r) {
        return r * 180.0 / Math.PI;
    }

    function deg360(d) {
        var v = d - 360.0 * Math.floor(d / 360.0);
        return v;
    }
}
