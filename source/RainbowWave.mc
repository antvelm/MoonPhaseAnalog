using Toybox.Application;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// The once-a-day rainbow wave.
//
// A band of spectrum expands from the hub past the rim. Watch faces are only
// redrawn once a second while awake, so this is a 12-frame sequence, not a
// smooth animation -- the band is made wide enough that each step still reads
// as motion rather than as a jump.
//
// Every colour on the dial is passed through tint() while a wave is running,
// which is what makes the wash cross the whole face rather than one layer.
module RainbowWave {

    const DURATION_SEC = 12;
    const BAND_FRAC    = 0.13;    // half-width of the band, fraction of radius
    const REACH        = 1.28;    // travel past the rim, so it exits cleanly
    const STORAGE_KEY  = "lastWaveDay";

    var _cx = 0;
    var _cy = 0;
    var _radius = 1.0;

    var _active = false;
    var _startEpoch = null;
    var _bandR = 0.0;
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
            // simulator without waiting a day.
            return clock.sec == 0;
        }
        if (!Settings.enableRainbowWave) { return false; }
        if (clock.hour < Settings.waveHour) { return false; }

        var today = todayValue();
        if (today == null) { return false; }

        var last = null;
        try {
            last = Application.Storage.getValue(STORAGE_KEY);
        } catch (e) {
            last = null;
        }

        // Strictly greater, so scrubbing the clock backwards in the simulator
        // does not re-fire the wave on every jump.
        if (last != null && !(today > last)) { return false; }

        try {
            Application.Storage.setValue(STORAGE_KEY, today);
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
        var hue = _hue + (r / _radius) * 140.0;
        hue = hue - 360.0 * Math.floor(hue / 360.0);
        return Theme.blend(color, Theme.hsvToColor(hue, 0.92, 1.0), t * 0.92);
    }
}
