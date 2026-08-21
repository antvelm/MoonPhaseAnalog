using Toybox.WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Lang;

// Minimal-futurist analog face:
//   - static layer in monochrome (dial, ticks, hands)
//   - the only colour is the moving second hand + its comet tail (hue sweep)
//   - warm procedural moon-phase subdial at 6 o'clock
//   - day at 3 o'clock, heart rate at 9 o'clock
// Everything is derived from the screen radius, so one code path serves both
// the Venu 3 (454x454) and Venu 3S (390x390).
class MoonPhaseAnalogView extends WatchUi.WatchFace {

    // Fixed lunar near-side maria in normalised disc coords (-1..1) with radius.
    // The moon is tidally locked, so this pattern never moves; only the
    // terminator sweeps across it.
    const CRATERS = [
        [-0.30, -0.42, 0.26],   // Mare Imbrium
        [ 0.18, -0.30, 0.20],   // Mare Serenitatis
        [ 0.34,  0.04, 0.17],   // Mare Tranquillitatis
        [ 0.55, -0.34, 0.13],   // Mare Crisium
        [-0.52,  0.10, 0.22],   // Oceanus Procellarum
        [ 0.02,  0.62, 0.06]    // Tycho (small bright point)
    ];

    var _w, _h, _cx, _cy, _radius, _scale;
    var _ox, _oy;            // burn-in shift, applied at draw time
    var _lowPower;
    var _burnIn;
    var _stars;              // precomputed [x,y] star field (Array of [x,y])

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
        _buildStars();
    }

    function onEnterSleep() {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var clock = System.getClockTime();

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

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var awake = !_lowPower;

        if (awake) {
            drawStarfield(dc);
            drawOrbitRing(dc);
        }
        drawTicks(dc, clock.sec, awake);
        drawTwelve(dc, awake);

        drawDay(dc, awake);
        drawHeartRate(dc, awake);
        drawMoon(dc, awake);

        drawHands(dc, clock, awake);
    }

    // --- Ornament -----------------------------------------------------------

    function _buildStars() {
        // A dozen fixed pseudo-random stars, dim, behind the hands.
        var seeds = [
            [-0.55, -0.60], [0.40, -0.66], [0.66, -0.30], [-0.70, -0.18],
            [0.58, 0.28], [-0.44, 0.52], [0.20, -0.44], [-0.24, -0.30],
            [0.48, -0.10], [-0.62, 0.30], [0.10, 0.40], [0.34, 0.58]
        ];
        _stars = [];
        for (var i = 0; i < seeds.size(); i += 1) {
            var sx = _cx + seeds[i][0] * _radius;
            var sy = _cy + seeds[i][1] * _radius;
            _stars.add([sx, sy]);
        }
    }

    (:typecheck(false))
    function drawStarfield(dc) {
        dc.setColor(Theme.STAR, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < _stars.size(); i += 1) {
            dc.fillCircle(_stars[i][0] + _ox, _stars[i][1] + _oy, 1);
        }
    }

    function drawOrbitRing(dc) {
        var r = _radius * 0.60;
        var n = 72;
        dc.setColor(Theme.ORBIT_RING, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i += 1) {
            var a = (i / (n * 1.0)) * 2.0 * Math.PI;
            var x = _cx + r * Math.sin(a) + _ox;
            var y = _cy - r * Math.cos(a) + _oy;
            dc.fillCircle(x, y, 1);
        }
    }

    // --- Tick ring + comet tail --------------------------------------------

    function drawTicks(dc, sec, awake) {
        var rTick = _radius * 0.92;
        for (var i = 0; i < 60; i += 1) {
            var a = (i / 60.0) * 2.0 * Math.PI;
            var x = _cx + rTick * Math.sin(a) + _ox;
            var y = _cy - rTick * Math.cos(a) + _oy;
            if (i % 15 == 0) {
                dc.setColor(Theme.TICK_MAJOR, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, scaled(3));
            } else {
                dc.setColor(Theme.TICK_DIM, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, scaled(2));
            }
        }

        if (!awake) { return; }

        // Comet tail: the eight dots behind the second hand glow in the
        // current hue and fade out.
        var hue = Theme.hueForSecond(sec);
        var baseColor = Theme.hsvToColor(hue, 1.0, 1.0);
        var r = (baseColor >> 16) & 0xFF;
        var g = (baseColor >> 8) & 0xFF;
        var b = baseColor & 0xFF;
        for (var k = 0; k < 8; k += 1) {
            var idx = ((sec - k) % 60 + 60) % 60;
            var a = (idx / 60.0) * 2.0 * Math.PI;
            var x = _cx + rTick * Math.sin(a) + _ox;
            var y = _cy - rTick * Math.cos(a) + _oy;
            var alpha = 210 - k * 24;
            if (alpha < 20) { alpha = 20; }
            var c = Gfx.createColor(alpha, r, g, b);
            dc.setColor(c, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, scaled(3) - (k > 4 ? 1 : 0));
        }
    }

    function drawTwelve(dc, awake) {
        dc.setColor(awake ? Theme.NUMERAL : Theme.READOUT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(_cx + _ox, _cy - _radius * 0.80 + _oy,
            Gfx.FONT_TINY, "12",
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // --- Complications ------------------------------------------------------

    function drawDay(dc, awake) {
        var day = Complications.dayOfMonth();
        var x = _cx + _radius * 0.50 + _ox;
        var y = _cy + _oy;
        dc.setColor(awake ? Theme.READOUT : Theme.READOUT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_NUMBER_MEDIUM, day.toString(),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function drawHeartRate(dc, awake) {
        var hr = Complications.heartRate();
        var cx = _cx - _radius * 0.50 + _ox;
        var cy = _cy + _oy;

        // Small heart glyph above the number.
        var hs = scaled(5);
        var hy = cy - scaled(16);
        dc.setColor(awake ? Theme.HR_HEART : Theme.READOUT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx - hs * 0.5, hy, hs * 0.6);
        dc.fillCircle(cx + hs * 0.5, hy, hs * 0.6);
        dc.fillPolygon([
            [cx - hs, hy + hs * 0.2],
            [cx + hs, hy + hs * 0.2],
            [cx, hy + hs * 1.3]
        ]);

        var text = (hr == null) ? "--" : hr.toString();
        dc.setColor(awake ? Theme.READOUT : Theme.READOUT_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + scaled(6), Gfx.FONT_TINY, text,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // --- Moon subdial -------------------------------------------------------

    function drawMoon(dc, awake) {
        var mx = _cx + _ox;
        var my = _cy + _radius * 0.46 + _oy;
        var mr = _radius * 0.15;
        var frac = MoonPhase.fraction();

        // Unlit disc + outline.
        dc.setColor(Theme.MOON_DARK, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, mr);
        dc.setColor(Theme.MOON_OUTLINE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(mx, my, mr);

        var cosP = Math.cos(2.0 * Math.PI * frac);
        var litColor = awake ? Theme.MOON_LIT : Theme.MOON_LOW;
        var mareColor = awake ? Theme.MOON_MARE : Theme.MOON_DARK;
        var waxing = (frac <= 0.5);

        var r2 = mr * mr;
        var step = 1;
        for (var dy = -mr; dy <= mr; dy += step) {
            var w = Math.sqrt(r2 - dy * dy);
            if (w <= 0) { continue; }
            var xt = w * cosP;

            var lx0; var lx1;
            if (waxing) {
                lx0 = xt; lx1 = w;      // lit from terminator to right limb
            } else {
                lx0 = -w; lx1 = -xt;    // lit from left limb to terminator
            }
            if (lx1 <= lx0) { continue; }

            var y = my + dy;
            dc.setColor(litColor, Gfx.COLOR_TRANSPARENT);
            dc.drawLine(mx + lx0, y, mx + lx1, y);

            if (awake) {
                drawCraterSpans(dc, mx, my, mr, dy, lx0, lx1, mareColor);
            }
        }

        // Limb highlight on the lit outer edge.
        if (awake) {
            dc.setColor(Theme.MOON_LIMB, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            if (waxing) {
                dc.drawArc(mx, my, mr - 1, Gfx.ARC_CLOCKWISE, 90, -90);
            } else {
                dc.drawArc(mx, my, mr - 1, Gfx.ARC_COUNTER_CLOCKWISE, 90, 270);
            }
            dc.setPenWidth(1);
        }
    }

    // Overdraw the maria where they fall inside the lit span on this scanline.
    function drawCraterSpans(dc, mx, my, mr, dy, lx0, lx1, mareColor) {
        dc.setColor(mareColor, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < CRATERS.size(); i += 1) {
            var ccx = CRATERS[i][0] * mr;
            var ccy = CRATERS[i][1] * mr;
            var ccr = CRATERS[i][2] * mr;
            var d = ccr * ccr - (dy - ccy) * (dy - ccy);
            if (d <= 0) { continue; }
            var half = Math.sqrt(d);
            var cx0 = ccx - half;
            var cx1 = ccx + half;
            // intersect [cx0,cx1] with lit [lx0,lx1]
            var a = (cx0 > lx0) ? cx0 : lx0;
            var b = (cx1 < lx1) ? cx1 : lx1;
            if (b > a) {
                var y = my + dy;
                dc.drawLine(mx + a, y, mx + b, y);
            }
        }
    }

    // --- Hands --------------------------------------------------------------

    function drawHands(dc, clock, awake) {
        var hour = clock.hour % 12;
        var min = clock.min;
        var sec = clock.sec;

        var hourAngle = ((hour + min / 60.0) / 12.0) * 2.0 * Math.PI;
        var minAngle  = ((min + sec / 60.0) / 60.0) * 2.0 * Math.PI;

        // Hour hand: short and wide.
        drawHand(dc, hourAngle, _radius * 0.52, scaled(9), scaled(18),
            awake ? Theme.HAND_FILL : null,
            awake ? Theme.HAND_OUTLINE : Theme.HAND_DIM);

        // Minute hand: long and narrow.
        drawHand(dc, minAngle, _radius * 0.82, scaled(6), scaled(20),
            awake ? Theme.HAND_FILL : null,
            awake ? Theme.HAND_OUTLINE : Theme.HAND_DIM);

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

    // Draw a hollow geometric blade hand. spineColor null => outline only.
    function drawHand(dc, angle, length, halfWidth, tail, spineColor, outlineColor) {
        var ca = Math.cos(angle);
        var sa = Math.sin(angle);

        var outer = handPoints(ca, sa, length, halfWidth, tail);
        dc.setColor(outlineColor, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(outer);

        // Hollow it out with the background colour.
        var inner = handPoints(ca, sa, length - scaled(4), halfWidth * 0.5, tail * 0.5);
        dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(inner);

        if (spineColor != null) {
            var spine = handPoints(ca, sa, length - scaled(3), halfWidth * 0.20, tail * 0.4);
            dc.setColor(spineColor, Gfx.COLOR_TRANSPARENT);
            dc.fillPolygon(spine);
        }
    }

    function handPoints(ca, sa, length, halfWidth, tail) {
        return [
            rot(0, -length, ca, sa),
            rot(halfWidth, -length * 0.5, ca, sa),
            rot(halfWidth * 0.6, tail, ca, sa),
            rot(-halfWidth * 0.6, tail, ca, sa),
            rot(-halfWidth, -length * 0.5, ca, sa)
        ];
    }

    // Rotate local (lx,ly) [tip toward -y] by hand angle, translate to centre
    // (with burn-in shift). See plan for the derivation.
    function rot(lx, ly, ca, sa) {
        var x = _cx + lx * ca - ly * sa + _ox;
        var y = _cy + lx * sa + ly * ca + _oy;
        return [x, y];
    }

    function scaled(v) {
        return (v * _scale + 0.5).toNumber();
    }
}
