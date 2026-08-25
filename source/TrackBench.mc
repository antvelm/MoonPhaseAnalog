using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Application;

// A benchmark for the primitives the dial draws with, and the tool the two
// perf docs' numbers come from. Off by default: set ENABLED = true, build with
//
//   build.ps1 -Perf          (watch)
//   run-simulator.ps1 -Perf  (simulator)
//
// and read the arm table it draws over the dial. Each line is
// "name total-ms/calls-per-frame"; divide by (round * calls) for the unit cost.
//
// Two constraints shape this file, and between them they rule out the obvious
// "loop it ten thousand times and time it" approach:
//
//  - System.getTimer() resolves to ~15.6 ms in the simulator, so a single dot
//    cannot be timed there. Batching is the only way to get a number out of it.
//  - Connect IQ's watchdog counts VM instructions, 240,000 per callback, and
//    it is enforced in the simulator as well as on the watch. A batch big
//    enough to time in one frame trips it and the app dies with "Watchdog
//    Tripped Error - Code Executed Too Long".
//
// So each frame runs exactly ONE arm for its own call budget, adds the elapsed
// time to that arm's running total, and hands the next frame to the next arm.
// After ROUNDS complete cycles every arm has been timed over ROUNDS * CALLS[i]
// calls, which is far past the timer's resolution, and the quantisation error
// averages out instead of accumulating. One round per second, one arm per
// frame: a full run is ROUNDS * arms seconds, so about four minutes as set up
// here. The numbers stop moving long before the end.
//
// The bl454 arm asks the graphics pool for a full-screen BufferedBitmap. It
// succeeds in the simulator; if it does not on a watch, the catch records it
// and that arm reads 0.
(:perf)
module TrackBench {

    const ENABLED = false;
    const ROUNDS  = 24;

    // SHORT trims the run to the three arms that settle the one open question:
    // does this watch charge per draw call, or per pixel? A full eleven-arm run
    // needs minutes of screen-on time on the wrist. Three arms is one raise.
    //
    //   all three roughly equal  -> per call. The primitive does not matter;
    //                               cutting call count is the only lever.
    //   c2aa far above the rest  -> per pixel, as in the simulator.
    const SHORT = true;
    const SHORT_ARMS = [0, 2, 7];       // ln3aa, c2aa, bl5

    // Calls per frame, per arm. Every arm is one primitive per call, so
    // ms / (ROUNDS * CALLS) is that primitive's unit cost. The big blits get a
    // smaller budget: at full screen a single one is not cheap, and the point
    // of those arms is the shape of the size curve, not a tight number.
    const CALLS = [
        900,   // ln3aa   3px drawLine, anti-aliased
        900,   // ln3no   3px drawLine, anti-alias off
        900,   // c2aa    fillCircle r=2, anti-aliased      <- what ships
        900,   // c2no    fillCircle r=2, anti-alias off
        900,   // rect2   filled disc as 3 fillRectangles
        900,   // sq4     one 4x4 fillRectangle
        900,   // setcol  setColor alone
        900,   // bl5     drawBitmap of the 5x5 star sprite
        300,   // bl64    drawBitmap of a 64x64 buffered bitmap
        60,    // bl227   drawBitmap of a 227x227 buffered bitmap
        20     // bl454   drawBitmap of a full-screen buffered bitmap
    ];

    const NAMES = [
        "ln3aa", "ln3no", "c2aa", "c2no", "rect2", "sq4",
        "setcol", "bl5", "bl64", "bl227", "bl454"
    ];

    var _x    = null;
    var _y    = null;
    var _col  = null;
    var _ms   = null;
    var _arm   = 0;
    var _round = 0;

    var _star5 = null;       // the shipped 5x5 star sprite, as an anchor
    var _b64   = null;       // transparent buffered bitmaps, three sizes
    var _b227  = null;
    var _b454  = null;
    var _big   = null;       // "created OK" flags, drawn in the report

    (:typecheck(false))
    function build(dc) {
        var cx = dc.getWidth()  / 2.0;
        var cy = dc.getHeight() / 2.0;
        var r  = cx * 0.94;
        _x   = new [60];
        _y   = new [60];
        _col = new [60];
        for (var i = 0; i < 60; i += 1) {
            var a = (i / 60.0) * 2.0 * Math.PI;
            _x[i] = (cx + r * Math.sin(a)).toNumber();
            _y[i] = (cy - r * Math.cos(a)).toNumber();
            // Vary it so no setColor can be short-circuited as "already set".
            _col[i] = 0x203040 + i * 0x030201;
        }
        _ms = new [NAMES.size()];
        for (var j = 0; j < NAMES.size(); j += 1) { _ms[j] = 0; }

        _star5 = Dial.lockedBitmap(Rez.Drawables.Star5);
        _big = "";
        _b64  = makeBuffer(64,  64);
        _b227 = makeBuffer(227, 227);
        _b454 = makeBuffer(dc.getWidth(), dc.getHeight());
    }

    // A transparent buffered bitmap with a couple of dots on it, which is what
    // a pre-rendered second-track ring would be. Returns null if the graphics
    // pool will not give it up -- which is itself the answer for that size.
    (:typecheck(false))
    function makeBuffer(w, h) {
        var ref = null;
        try {
            ref = Gfx.createBufferedBitmap({ :width => w, :height => h });
        } catch (e) {
            _big = _big + "x" + w + " ";
            return null;
        }
        if (ref == null) { _big = _big + "n" + w + " "; return null; }
        var bmp = (ref has :get) ? ref.get() : ref;
        var bdc = bmp.getDc();
        bdc.setColor(Gfx.COLOR_TRANSPARENT, Gfx.COLOR_TRANSPARENT);
        bdc.clear();
        bdc.setColor(0x404850, Gfx.COLOR_TRANSPARENT);
        for (var i = 4; i < w - 4; i += 12) {
            bdc.fillCircle(i, h / 2, 2);
        }
        _big = _big + "ok" + w + " ";
        return bmp;
    }

    // --- arms ---------------------------------------------------------------

    (:typecheck(false))
    function armLine(dc, aa) {
        if (dc has :setAntiAlias) { dc.setAntiAlias(aa); }
        var t0 = System.getTimer();
        for (var n = 0; n < 15; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                var x = _x[i];
                dc.drawLine(x - 1, _y[i], x + 2, _y[i]);
            }
        }
        var t = System.getTimer() - t0;
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        return t;
    }

    (:typecheck(false))
    function armCircle(dc, rad, aa) {
        if (dc has :setAntiAlias) { dc.setAntiAlias(aa); }
        var t0 = System.getTimer();
        for (var n = 0; n < 15; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                dc.fillCircle(_x[i], _y[i], rad);
            }
        }
        var t = System.getTimer() - t0;
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        return t;
    }

    // Bresenham spans, runs of equal width collapsed: r=2 is 3,5,5,5,3 wide.
    // Three calls, not one, which is the whole point of timing it.
    (:typecheck(false))
    function armRect2(dc) {
        var t0 = System.getTimer();
        for (var n = 0; n < 5; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                var x = _x[i];
                var y = _y[i];
                dc.fillRectangle(x - 2, y - 1, 5, 3);
                dc.fillRectangle(x - 1, y - 2, 3, 1);
                dc.fillRectangle(x - 1, y + 2, 3, 1);
            }
        }
        return System.getTimer() - t0;
    }

    (:typecheck(false))
    function armSquare(dc) {
        var t0 = System.getTimer();
        for (var n = 0; n < 15; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                dc.fillRectangle(_x[i] - 2, _y[i] - 2, 4, 4);
            }
        }
        return System.getTimer() - t0;
    }

    (:typecheck(false))
    function armSetColor(dc) {
        var t0 = System.getTimer();
        for (var n = 0; n < 15; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                dc.setColor(_col[i], Gfx.COLOR_TRANSPARENT);
            }
        }
        return System.getTimer() - t0;
    }

    (:typecheck(false))
    function armBlit(dc, bmp, calls) {
        if (bmp == null) { return 0; }
        var t0 = System.getTimer();
        for (var n = 0; n < calls; n += 1) {
            dc.drawBitmap(0, 0, bmp);
        }
        return System.getTimer() - t0;
    }

    (:typecheck(false))
    function armBlitSmall(dc) {
        if (_star5 == null) { return 0; }
        var t0 = System.getTimer();
        for (var n = 0; n < 15; n += 1) {
            for (var i = 0; i < 60; i += 1) {
                dc.drawBitmap(_x[i] - 2, _y[i] - 2, _star5);
            }
        }
        return System.getTimer() - t0;
    }

    function armCount() {
        return SHORT ? SHORT_ARMS.size() : NAMES.size();
    }

    (:typecheck(false))
    function armAt(slot) {
        return SHORT ? SHORT_ARMS[slot] : slot;
    }

    (:typecheck(false))
    function runArm(dc, which) {
        if (which == 0)  { return armLine(dc, true); }
        if (which == 1)  { return armLine(dc, false); }
        if (which == 2)  { return armCircle(dc, 2, true); }
        if (which == 3)  { return armCircle(dc, 2, false); }
        if (which == 4)  { return armRect2(dc); }
        if (which == 5)  { return armSquare(dc); }
        if (which == 6)  { return armSetColor(dc); }
        if (which == 7)  { return armBlitSmall(dc); }
        if (which == 8)  { return armBlit(dc, _b64, 300); }
        if (which == 9)  { return armBlit(dc, _b227, 60); }
        return armBlit(dc, _b454, 20);
    }

    // --- driver -------------------------------------------------------------

    (:typecheck(false))
    function run(dc) {
        if (!ENABLED) { return; }
        if (_x == null) { build(dc); }

        if (_round < ROUNDS) {
            var t = runArm(dc, armAt(_arm));
            // Round 0 is a warm-up: cold caches, and the graphics pool has not
            // settled. Time it anyway so the pacing is identical, then throw
            // the number away.
            if (_round > 0) { _ms[armAt(_arm)] += t; }
            _arm += 1;
            if (_arm >= armCount()) {
                _arm = 0;
                _round += 1;
            }
        }
        report(dc);
    }

    (:typecheck(false))
    function report(dc) {
        dc.setColor(0x000000, 0x000000);
        dc.clear();
        var font = Gfx.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var w  = dc.getWidth();
        var y0 = dc.getHeight() * 0.24;
        var done = (_round > 0) ? (_round - 1) : 0;
        dc.setColor((_round >= ROUNDS) ? 0x00FF00 : 0xFFAA00, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y0 - lh * 2.2, font, "round " + done + "/" + (ROUNDS - 1),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w / 2, y0 - lh * 1.2, font, _big,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        for (var slot = 0; slot < armCount(); slot += 1) {
            var i = armAt(slot);
            var col = SHORT ? (w * 0.5) : ((slot < 6) ? (w * 0.28) : (w * 0.72));
            var row = SHORT ? slot : ((slot < 6) ? slot : (slot - 6));
            dc.drawText(col, y0 + row * lh, font,
                        NAMES[i] + " " + _ms[i] + "/" + CALLS[i],
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }
}

(:noperf)
module TrackBench {
    function run(dc) {
    }
}
