using Toybox.Application;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// The recurring rainbow wave.
//
// A ring of spectrum expands from the hub past the rim. Watch faces are only
// redrawn once a second while awake, so this is an 8-frame sequence, not a
// smooth animation -- the band is made wide enough that each step still reads
// as motion rather than as a jump.
//
// The wash is deliberately partial: only the dial's own marks go through
// tint() -- the second-track dots and comet, the hour numerals and ticks, the
// 5-second numerals and the background stars. The hands, the moon, the date and
// heart-rate readouts and the ornamental lines (orbit ring, zodiac joins) are
// left alone, so the wave crosses behind the time rather than swallowing it.
module RainbowWave {

    // Eight seconds, because that is about how long the screen stays in high
    // power after a wrist raise: a longer wave gets cut off before it reaches
    // the rim and has to be replayed on the next raise to be seen whole.
    const DURATION_SEC = 8;
    // Half-width of the band, as a fraction of the radius. It has to stay above
    // half the per-frame step (REACH / DURATION_SEC = 0.16R) or the ring breaks
    // into separate rings instead of reading as one moving band.
    const BAND_FRAC    = 0.13;
    const REACH        = 1.28;    // travel past the rim, so it exits cleanly
    const STORAGE_KEY  = "lastWaveSlot";

    // A slot only counts as spent once its wave has run end to end. The watch
    // wakes for a few seconds on any arm movement, not just on a real look, and
    // recording the slot on the first frame meant one stray gesture swallowed
    // the whole three-hour slot -- the wave "fired" to a screen nobody watched
    // and then never came back. Leaving the slot uncommitted lets the next
    // wrist raise replay it in full. The cap stops that repeating for ever on
    // watches whose wake window is shorter than the wave itself.
    const MAX_ATTEMPTS = 3;

    var _cx = 0;
    var _cy = 0;
    var _radius = 1.0;

    var _active = false;
    var _startEpoch = null;
    var _pendingKey = null;       // slot the running wave belongs to, stored when it finishes
    var _attemptKey = null;       // slot _attempts is counting for
    var _attempts = 0;
    var _bandR = 0.0;             // band radius: how far out the ring has reached
    var _bandHalf = 1.0;
    var _hue = 0.0;

    // Cached verdict from shouldStart(). Reaching that verdict costs a date
    // lookup and a persistent-storage read, and it was paying both once a
    // second for an answer that can only change when the hour does -- slots
    // sit on hour boundaries. Cached against the hour and the two settings
    // that define the schedule, the real check runs a couple of dozen times a
    // day instead of 86,400.
    var _dueHour = -1;            // clock hour the verdict was computed for
    var _dueStart = -1;           // Settings.waveHour it assumed
    var _dueInterval = -1;        // Settings.waveIntervalHours it assumed
    var _dueSlot = null;          // slot to spend, or null for "nothing due"

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
            // Going back to sleep mid-wave abandons it. The slot is only given
            // up once the retries are used, so an unwatched gesture wake costs
            // nothing and the next raise shows the wave from the start.
            if (_startEpoch != null && _attempts >= MAX_ATTEMPTS) { commitSlot(); }
            _active = false;
            _startEpoch = null;
            _pendingKey = null;
            return;
        }

        if (_startEpoch == null && shouldStart(clock)) {
            _startEpoch = epochSeconds;
            countAttempt();
        }

        if (_startEpoch == null) {
            _active = false;
            return;
        }

        var elapsed = epochSeconds - _startEpoch;
        if (elapsed < 0 || elapsed > DURATION_SEC) {
            // Past the end is a wave that was actually shown; a negative
            // elapsed is the clock being scrubbed backwards, which is not.
            if (elapsed > DURATION_SEC) { commitSlot(); }
            _active = false;
            _startEpoch = null;
            _pendingKey = null;
            return;
        }

        var p = elapsed / (DURATION_SEC * 1.0);
        _active = true;
        _bandR = p * _radius * REACH;
        _hue = p * 300.0;
    }

    // Whether a wave is due. Nothing is written here: the slot it would spend
    // is parked in _pendingKey and only recorded by commitSlot() once the wave
    // has been seen through.
    (:typecheck(false))
    function shouldStart(clock) {
        _pendingKey = null;

        if (Settings.waveTestMode) {
            // Fire at the top of every minute so the effect can be tuned in the
            // simulator without waiting for the next slot.
            return clock.sec == 0;
        }
        if (!Settings.enableRainbowWave) { return false; }

        if (clock.hour == _dueHour
                && Settings.waveHour == _dueStart
                && Settings.waveIntervalHours == _dueInterval) {
            _pendingKey = _dueSlot;
            return _dueSlot != null;
        }

        // Whatever this frame works out, it holds for the rest of the hour.
        _dueHour = clock.hour;
        _dueStart = Settings.waveHour;
        _dueInterval = Settings.waveIntervalHours;
        _dueSlot = null;

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

        _dueSlot = key;
        _pendingKey = key;
        return true;
    }

    // Record the slot, now that its wave has been shown.
    (:typecheck(false))
    function commitSlot() {
        if (_pendingKey == null) { return; }     // test mode has no slot to spend
        try {
            Application.Storage.setValue(STORAGE_KEY, _pendingKey);
        } catch (e) {
            // If it cannot be stored the wave may repeat; not worth failing over.
        }
        _pendingKey = null;

        // The stored slot has moved on, so the cached verdict for this hour is
        // stale -- it still says a wave is due. Force one more real check.
        _dueHour = -1;
    }

    // Count this run at the current slot, resetting when the slot moves on.
    (:typecheck(false))
    function countAttempt() {
        if (_pendingKey == null) { return; }
        if (_attemptKey == null || _attemptKey != _pendingKey) {
            _attemptKey = _pendingKey;
            _attempts = 0;
        }
        _attempts += 1;
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
