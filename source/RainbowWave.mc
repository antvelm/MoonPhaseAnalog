using Toybox.Application;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// The recurring rainbow wave.
//
// A ring of spectrum expands from the hub past the rim. Watch faces are only
// redrawn once a second while awake, so this is a 12-frame sequence, not a
// smooth animation -- the band is made wide enough that each step still reads
// as motion rather than as a jump.
//
// The wash is deliberately partial: only the dial's marks and numbers are
// passed through tint() (the second-track dots and comet, the hour numerals and
// ticks, the 5-second numerals, the stars and the date). The hands, the moon,
// the heart-rate readout and the ornamental lines are left alone, so the wave
// crosses behind the time rather than swallowing it.
module RainbowWave {

    const DURATION_SEC = 12;
    const BAND_FRAC    = 0.13;    // half-width of the band, fraction of radius
    const REACH        = 1.28;    // travel past the rim, so it exits cleanly
    const STORAGE_KEY  = "lastWaveSlot";

    var _cx = 0;
    var _cy = 0;
    var _radius = 1.0;

    var _active = false;
    var _startEpoch = null;
    var _bandR = 0.0;             // band radius: how far out the ring has reached
    var _bandHalf = 1.0;
    var _hue = 0.0;

    function setup(cx, cy, radius) {
        _cx = cx;
        _cy = cy;
        _radius = radius;
        _bandHalf = radius * BAND_FRAC;
    }

    function isActive() {
        return _active;
    }

    // Called once at the top of every onUpdate.
    (:typecheck(false))
    function update(epochSeconds, clock, awake) {
        if (!awake) {
            _active = false;
            _startEpoch = null;
            return;
        }

        if (_startEpoch == null && shouldStart(clock)) {
            _startEpoch = epochSeconds;
        }

        if (_startEpoch == null) {
            _active = false;
            return;
        }

        var elapsed = epochSeconds - _startEpoch;
        if (elapsed < 0 || elapsed > DURATION_SEC) {
            _active = false;
            _startEpoch = null;
            return;
        }

        var p = elapsed / (DURATION_SEC * 1.0);
        _active = true;
        _bandR = p * _radius * REACH;
        _hue = p * 300.0;
    }

    (:typecheck(false))
    function shouldStart(clock) {
        if (Settings.waveTestMode) {
            // Fire at the top of every minute so the effect can be tuned in the
            // simulator without waiting for the next slot.
            return clock.sec == 0;
        }
        if (!Settings.enableRainbowWave) { return false; }
        if (clock.hour < Settings.waveHour) { return false; }

        var today = todayValue();
        if (today == null) { return false; }

        // Slots run from WaveHour onwards at WaveIntervalHours spacing: with the
        // defaults (0 and 3) that is 00:00, 03:00 ... 21:00. Adding the slot to
        // the local midnight epoch gives a key that still rises across days,
        // since consecutive days are 86400 apart and a slot never reaches 24.
        var slot = (clock.hour - Settings.waveHour) / Settings.waveIntervalHours;
        var key = today + slot;

        var last = null;
        try {
            last = Application.Storage.getValue(STORAGE_KEY);
        } catch (e) {
            last = null;
        }

        // Strictly greater, so scrubbing the clock backwards in the simulator
        // does not re-fire the wave on every jump.
        if (last != null && !(key > last)) { return false; }

        try {
            Application.Storage.setValue(STORAGE_KEY, key);
        } catch (e) {
            // If it cannot be stored the wave may repeat; not worth failing over.
        }
        return true;
    }

    (:typecheck(false))
    function todayValue() {
        try {
            return Time.today().value();
        } catch (e) {
            return null;
        }
    }

    // Recolour a point if the band is passing over it. This is called for every
    // mark on the dial, so the inactive path returns immediately.
    (:typecheck(false))
    function tint(color, x, y) {
        if (!_active) { return color; }

        var dx = x - _cx;
        var dy = y - _cy;
        var r = Math.sqrt(dx * dx + dy * dy);
        var d = r - _bandR;
        if (d < 0) { d = -d; }
        if (d >= _bandHalf) { return color; }

        var t = 1.0 - d / _bandHalf;
        return Theme.blend(color, hueAt(r), t * 0.92);
    }

    // The colour tint() would blend towards, or null where the band is not
    // reaching -- for callers that cannot blend a source colour themselves,
    // such as the blitted 5-second numerals.
    (:typecheck(false))
    function tintColor(x, y) {
        if (!_active) { return null; }

        var dx = x - _cx;
        var dy = y - _cy;
        var r = Math.sqrt(dx * dx + dy * dy);
        var d = r - _bandR;
        if (d < 0) { d = -d; }
        if (d >= _bandHalf) { return null; }

        return hueAt(r);
    }

    // The band is not one flat colour: the hue also runs with distance from the
    // hub, so the ring shows a spread of the spectrum rather than a single tone.
    (:typecheck(false))
    function hueAt(r) {
        var hue = _hue + (r / _radius) * 140.0;
        hue = hue - 360.0 * Math.floor(hue / 360.0);
        return Theme.hsvToColor(hue, 0.92, 1.0);
    }
}
