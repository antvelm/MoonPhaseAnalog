using Toybox.WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Time;
using Toybox.Lang;

// Minimal-futurist analog face:
//   - second track at 0.90R: 48 tick dots and 12 radial numerals on one ring,
//     with the spectrum comet riding the same ring
//   - hour numerals at 0.76R in bright white
//   - selectable hand style over a starfield or a zodiac constellation
//   - procedural moon-phase subdial at 6 o'clock, which turns copper during a
//     lunar eclipse and shows a corona during a solar one
//   - "FRI 27" date at 3 o'clock, heart rate at 9 o'clock
//   - every few hours, a rainbow wave washes outward across the dial's
//     numbers, marks and stars
//
// This class owns layout and ordering; the drawing lives in Dial, Hands and
// MoonDial. Everything is derived from the screen radius, so one code path
// serves both the Venu 3 (454x454) and Venu 3S (390x390).
class MoonPhaseAnalogView extends WatchUi.WatchFace {

    // -----------------------------------------------------------------------
    // TUNING: complication size and placement. Radii are fractions of the
    // screen radius, so they hold on both watch sizes. The dial's own
    // proportions (ring radii, numeral fonts) live in Dial.mc.
    // -----------------------------------------------------------------------

    // The side pair sits closer in than the moon: with hour numerals at 0.76R
    // they have to clear the 3 and the 9, and the date is the widest thing on
    // the dial.
    const R_SIDE = 0.38;
    const R_MOON = 0.46;

    // Date, as "FRI 27". DATE_FONT is the number; DOW_FONT the weekday.
    const DOW_FONT  = Gfx.FONT_XTINY;
    const DATE_FONT = Gfx.FONT_MEDIUM;

    // Heart rate. HR_ICON is the glyph half-size in pixels before scaling to
    // the watch, so it tracks the font if you change one of them.
    const HR_FONT = Gfx.FONT_MEDIUM;
    const HR_ICON = 9;

    var _w, _h, _cx, _cy, _radius, _scale;
    var _ox, _oy;            // burn-in shift, applied at draw time
    var _lowPower;
    var _burnIn;
    var _lastStarCount;
    var _lastBackground;
    var _redMoonBitmap;

    function initialize() {
        WatchFace.initialize();
        _lowPower = false;
        _burnIn = false;
        _ox = 0;
        _oy = 0;
    }

    function onLayout(dc) {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _radius = (_w < _h ? _w : _h) / 2.0;
        _scale = _radius / 227.0;      // 227 = Venu 3 radius; scales to 3S
        var settings = System.getDeviceSettings();
        _burnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;

        Settings.load();
        _lastStarCount = Settings.starCount;
        _lastBackground = Settings.background;

        Dial.setup(dc, _cx, _cy, _radius, _scale);
        RainbowWave.setup(_cx, _cy, _radius);

        _redMoonBitmap = WatchUi.loadResource(Rez.Drawables.RedMoon);
    }

    // Settings that change cached geometry need it rebuilt, which cannot happen
    // in onSettingsChanged because there is no Dc there.
    (:typecheck(false))
    function refreshCaches() {
        if (Settings.starCount != _lastStarCount) {
            _lastStarCount = Settings.starCount;
            Dial.buildStars();
        }
    }

    function onEnterSleep() {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    (:typecheck(false))
    function onUpdate(dc) {
        Perf.begin();
        Settings.load();
        refreshCaches();
        Perf.mark();

        var clock = System.getClockTime();
        var now = Time.now().value();
        var awake = !_lowPower;

        // The starfield fades with moonlight, so the background needs the same
        // phase the disc draws. Taken once here, off the astro clock, so a debug
        // time offset moves the sky and the moon together.
        var frac = MoonPhase.fractionAt(astroTime(now));
        Perf.mark();

        // Burn-in shift: nudge the whole composition on a slow cycle in
        // always-on mode so no pixel is lit continuously.
        if (_lowPower && _burnIn) {
            var phase = clock.min % 4;
            _ox = (phase == 1 || phase == 2) ? scaled(3) : -scaled(3);
            _oy = (phase == 2 || phase == 3) ? scaled(3) : -scaled(3);
        } else {
            _ox = 0;
            _oy = 0;
        }

        if (RainbowWave.ENABLED) {
            RainbowWave.setup(_cx + _ox, _cy + _oy, _radius);
            RainbowWave.update(now, clock, awake);
        }
        Perf.mark();

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        Perf.mark();

        // Only the origin moves per frame; the cached track, labels and star
        // field were built once in onLayout.
        Dial.setOffset(_ox, _oy);
        Hands.setup(_cx + _ox, _cy + _oy, _scale, clock.sec);

        if (awake) {
            Dial.drawBackground(dc, clock.sec, frac);
            if (Settings.showOrbitRing) { Dial.drawOrbitRing(dc); }
        }
        Perf.mark();
        Dial.drawSecondTrack(dc, clock.sec, awake);
        Perf.mark();
        Dial.drawHourMarks(dc, awake);
        Perf.mark();

        drawDay(dc, awake);
        drawHeartRate(dc, awake);
        Perf.mark();
        drawMoon(dc, awake, now, frac);
        Perf.mark();
        //drawRedMoonSprite(dc);

        drawHands(dc, clock, awake);
        Perf.mark();

        TrackBench.run(dc);
        Perf.draw(dc);
    }

    // --- Complications ------------------------------------------------------

    // Classic "FRI 27": a small grey weekday followed by the day of the month,
    // measured so the pair as a whole sits on the complication centre.
    (:typecheck(false))
    function drawDay(dc, awake) {
        var dow = Complications.dayOfWeekShort();
        var day = Complications.dayOfMonth().toString();

        var dowFont = DOW_FONT;
        var dayFont = DATE_FONT;
        var gap = scaled(4);

        var dowW = dc.getTextWidthInPixels(dow, dowFont);
        var dayW = dc.getTextWidthInPixels(day, dayFont);
        var total = dowW + gap + dayW;

        var cx = _cx + _radius * R_SIDE + _ox;
        var cy = _cy + _oy;
        var left = cx - total / 2;

        var dowColor = awake ? Theme.DAY_WEEK : Theme.READOUT_DIM;
        var dayColor = awake ? Theme.READOUT : Theme.READOUT_DIM;

        // Neither half is tinted: like the heart rate opposite it, the date sits
        // out the rainbow wave, which colours the dial's own marks and numerals.
        dc.setColor(dowColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(left, cy, dowFont, dow,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);

        dc.setColor(dayColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(left + dowW + gap, cy, dayFont, day,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Glyph beside the number rather than above it, so the pair sits on one
    // line at the same height as the "FRI 27" date on the other side.
    (:typecheck(false))
    function drawHeartRate(dc, awake) {
        var hr = Complications.heartRate();
        var cx = _cx - _radius * R_SIDE + _ox;
        var cy = _cy + _oy;

        var text = (hr == null) ? "--" : hr.toString();
        var font = HR_FONT;
        var textW = dc.getTextWidthInPixels(text, font);

        var hs = scaled(HR_ICON);
        var gap = scaled(4);
        var iconW = hs * 1.92;
        var total = iconW + gap + textW;

        var left = cx - total / 2;
        var hx = left + iconW / 2;
        var tx = left + iconW + gap;

        drawHeart(dc, hx, cy, hs, awake);

        // Not tinted, glyph and number both: like the date opposite it, the
        // heart rate sits out the rainbow wave.
        dc.setColor(awake ? Theme.READOUT : Theme.READOUT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(tx, cy, font, text,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Two lobes and a point, with a cusp notch between the lobes so it reads as
    // a heart rather than a blob at this size. See drawHeartRate: the rainbow
    // wave passes the whole heart-rate readout by.
    (:typecheck(false))
    function drawHeart(dc, cx, cy, hs, awake) {
        var color = awake ? Theme.HR_HEART : Theme.READOUT_DIM;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);

        var lobe = hs * 0.52;
        dc.fillCircle(cx - hs * 0.45, cy - hs * 0.12, lobe);
        dc.fillCircle(cx + hs * 0.45, cy - hs * 0.12, lobe);
        dc.fillPolygon([
            [cx - hs * 0.96, cy + hs * 0.02],
            [cx - hs * 0.20, cy + hs * 0.58],
            [cx,             cy + hs * 1.05],
            [cx + hs * 0.20, cy + hs * 0.58],
            [cx + hs * 0.96, cy + hs * 0.02]
        ]);
        // Cusp: bite the notch back out of the top centre.
        dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [cx - hs * 0.18, cy - hs * 0.50],
            [cx + hs * 0.18, cy - hs * 0.50],
            [cx,             cy - hs * 0.10]
        ]);
    }

    // --- Moon ---------------------------------------------------------------

    (:typecheck(false))
    function drawMoon(dc, awake, now, frac) {
        var mx = _cx + _ox;
        var my = _cy + _radius * R_MOON + _oy;
        var mr = _radius * 0.15;

        var eclipse = currentEclipse(now);
        var weak = false;
        if (eclipse != null && !eclipse[:lunar]) {
            // A solar eclipse is only visible along a narrow path the face
            // cannot know about, so the corona is drawn faint unless the
            // location check actually ran and passed. "Always" never checks,
            // and a watch with no fix fails open: both are unconfirmed.
            // A forced eclipse is a rendering test, so never dim that one.
            weak = (Settings.debugEclipse == Settings.DEBUG_ECLIPSE_OFF)
                && !SkyPosition.visibilityConfirmed();
        }

        // frac is passed in rather than taken here: it has to come off the same
        // clock the eclipse did, or a debug time offset moves the eclipse while
        // the disc keeps today's phase. The starfield shares it too.
        MoonDial.draw(dc, mx, my, mr, awake, frac, eclipse, weak);
    }

    // The eclipse to render right now, or null. Cached inside MoonPhase, so
    // this is cheap to call every second.
    (:typecheck(false))
    function currentEclipse(now) {
        if (!Settings.eclipseEffects) { return null; }

        if (Settings.debugEclipse == Settings.DEBUG_ECLIPSE_LUNAR) {
            return { :type => EclipseData.TOTAL_LUNAR, :lunar => true,
                     :magnitude => 1.2, :offset => 0.0, :exact => false };
        }
        if (Settings.debugEclipse == Settings.DEBUG_ECLIPSE_SOLAR) {
            return { :type => EclipseData.TOTAL_SOLAR, :lunar => false,
                     :magnitude => 1.0, :offset => 0.0, :exact => false };
        }

        var e = MoonPhase.eclipseAt(astroTime(now));
        if (e == null) { return null; }

        // A penumbral lunar eclipse looks like nothing in the sky, so it is
        // detected and reported but never turns the moon red.
        if (e[:type] == EclipseData.PENUMBRAL) { return null; }

        if (!SkyPosition.eclipseVisible(e, now)) { return null; }
        return e;
    }

    // The clock the astronomy runs on. DebugTimeOffsetDays shifts only this, so
    // the face can be parked on an eclipse while still showing the real time.
    (:typecheck(false))
    function astroTime(now) {
        if (Settings.debugTimeOffsetDays == 0.0) { return now; }
        return now + Settings.debugTimeOffsetDays * 86400.0;
    }

    // Scratch: the red moon sprite, centred on the face at a fraction of the
    // screen radius so it reads as an accent rather than covering the dial.
    // drawScaledBitmap rather than drawBitmap2+transform: the resource
    // compiler palettises the PNG, and drawBitmap2 refuses a palettised
    // source once a :transform is supplied (see Dial.renderLabel).
    const RED_MOON_SPRITE_SCALE = 0.35; // sprite diameter as a fraction of _radius

    (:typecheck(false))
    function drawRedMoonSprite(dc) {
        if (_redMoonBitmap == null) { return; }

        var size = (_radius * RED_MOON_SPRITE_SCALE).toNumber();
        var x = (_cx + _ox - size / 2.0).toNumber();
        var y = (_cy + _oy - size / 2.0).toNumber() + _h / 4.4;

        dc.drawScaledBitmap(x, y, size, size, _redMoonBitmap);
    }

    // --- Hands --------------------------------------------------------------

    (:typecheck(false))
    function drawHands(dc, clock, awake) {
        var hour = clock.hour % 12;
        var min = clock.min;
        var sec = clock.sec;

        // Stepped hands: the minute hand ticks once a minute, the hour hand
        // every 10 minutes, so neither creeps between positions.
        var hourMin = (min / 10) * 10;
        var hourAngle = ((hour + hourMin / 60.0) / 12.0) * 2.0 * Math.PI;
        var minAngle  = (min / 60.0) * 2.0 * Math.PI;

        Hands.draw(dc, hourAngle, _radius * 0.48, scaled(11), scaled(6), scaled(16), awake);
        Hands.draw(dc, minAngle, _radius * 0.84, scaled(8), scaled(4), scaled(18), awake);

        // Second hand: hairline needle in the current hue (awake only).
        if (awake) {
            var secAngle = (sec / 60.0) * 2.0 * Math.PI;
            var secColor = Theme.hsvToColor(Theme.hueForSecond(sec), 1.0, 1.0);
            var ca = Math.cos(secAngle);
            var sa = Math.sin(secAngle);
            var tipX = _cx + _radius * 0.86 * sa + _ox;
            var tipY = _cy - _radius * 0.86 * ca + _oy;
            var tailX = _cx - _radius * 0.18 * sa + _ox;
            var tailY = _cy + _radius * 0.18 * ca + _oy;
            dc.setColor(secColor, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(scaled(2));
            dc.drawLine(tailX, tailY, tipX, tipY);
            dc.fillCircle(_cx + _ox, _cy + _oy, scaled(4));
            dc.setPenWidth(1);
        }

        // Centre hub.
        dc.setColor(Theme.HUB, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(_cx + _ox, _cy + _oy, scaled(4));
        dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(_cx + _ox, _cy + _oy, scaled(2));
    }

    function scaled(v) {
        return (v * _scale + 0.5).toNumber();
    }
}
