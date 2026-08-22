using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Lang;

// Everything on the dial except the hands, the moon and the complications:
// the second track, the hour numerals, the background ornament and the comet.
//
// ---------------------------------------------------------------------------
// TUNING: the dial's proportions all live in the constants directly below.
// Radii are fractions of the screen radius, so they hold on both watch sizes.
// ---------------------------------------------------------------------------
module Dial {

    // Where each ring sits. The second track is the outermost thing on the
    // face; the tick dots and the 5-second numerals share it.
    const R_SECOND = 0.94;
    const R_HOUR   = 0.78;
    const R_ORBIT  = 0.60;

    // --- Second numerals -----------------------------------------------------
    // FONT_XTINY is the smallest built-in font, so anything smaller than that
    // is reached by scaling the rendered label down as it is blitted. Lower
    // SEC_LABEL_SCALE for smaller numbers, raise it for larger; 1.0 is the
    // font's natural size.
    const SEC_LABEL_FONT  = Gfx.FONT_XTINY;
    const SEC_LABEL_SCALE = 0.65;//0.72

    // --- Hour marks -----------------------------------------------------------
    const HOUR_FONT       = Gfx.FONT_SMALL;
    // Used instead of HOUR_FONT when HourNumeralsOuter moves the hours out to
    // the second track's radius: bigger, so they still read at that distance.
    const HOUR_FONT_OUTER = Gfx.FONT_MEDIUM;

    // Radial tick lengths for HourMarkStyle's Lines modes, in pixels before
    // scaling. Major is used for the eight non-cardinal hours in the plain
    // Lines mode (12/3/6/9 get numerals instead), and at 12/3/6/9 only in the
    // cardinal-only mode; minor fills the other eight hours there. The pen
    // widths and colours of these ticks live in Theme (HOUR_TICK_*).
    const HOUR_TICK_MAJOR_LEN = 14;
    const HOUR_TICK_MINOR_LEN = 6;

    // Tick dot radii, in pixels before scaling to the watch size.
    const DOT_MINOR = 2;
    const DOT_MAJOR = 3;

    var _cx = 0;
    var _cy = 0;
    var _radius = 1.0;
    var _scale = 1.0;

    // Cached second labels: one bitmap per 5-second mark, rendered once in
    // setup() and only blitted afterwards.
    var _labels = null;
    var _labelW = 0;
    var _labelH = 0;
    var _canRotate = false;

    // Precomputed positions on the second track, [x, y] per second.
    var _trackX = null;
    var _trackY = null;

    var _ox = 0;                // burn-in shift, applied at draw time
    var _oy = 0;

    var _stars = null;          // flat: x, y, tier, brightness
    var _zodiacSign = -1;
    var _zodiacPts = null;      // flat: x, y, tier

    (:typecheck(false))
    function setup(dc, cx, cy, radius, scale) {
        _cx = cx;
        _cy = cy;
        _radius = radius;
        _scale = scale;
        _canRotate = (dc has :drawBitmap2);

        buildTrack();
        buildLabels(dc);
        buildStars();
        _zodiacSign = -1;       // force a rebuild on the next draw
    }

    // Burn-in shift. Separate from setup() so the cached geometry, labels and
    // star field are built once and only the origin moves each frame.
    function setOffset(ox, oy) {
        _ox = ox;
        _oy = oy;
    }

    function scaled(v) {
        return (v * _scale + 0.5).toNumber();
    }

    // --- Second track geometry ----------------------------------------------

    (:typecheck(false))
    function buildTrack() {
        var r = _radius * R_SECOND;
        _trackX = new [60];
        _trackY = new [60];
        for (var i = 0; i < 60; i += 1) {
            var a = (i / 60.0) * 2.0 * Math.PI;
            _trackX[i] = _cx + r * Math.sin(a);
            _trackY[i] = _cy - r * Math.cos(a);
        }
    }

    // --- Second numerals ----------------------------------------------------

    // Rasterise "60", "05" ... "55" once. Rotating text is not possible with
    // drawText, so each label is rendered into a small buffer that is then
    // blitted through an AffineTransform.
    (:typecheck(false))
    function buildLabels(dc) {
        _labels = null;
        if (!_canRotate) { return; }

        var font = SEC_LABEL_FONT;
        _labelW = dc.getTextWidthInPixels("00", font) + scaled(4);
        _labelH = Gfx.getFontHeight(font);

        _labels = new [12];

        for (var i = 0; i < 12; i += 1) {
            var value = (i == 0) ? 60 : i * 5;
            var text = value.format("%02d");
            // 60/15/30/45 carry the quarter emphasis the major tick dots used to.
            var tone = (i % 3 == 0) ? Theme.SEC_NUM_Q : Theme.SEC_NUMERAL;
            _labels[i] = renderLabel(text, font, tone);
        }
    }

    (:typecheck(false))
    function renderLabel(text, font, color) {
        // No :palette here: drawBitmap2 refuses a palettised source when a
        // transform is supplied, and the labels have to be rotated.
        var ref = Gfx.createBufferedBitmap({
            :width => _labelW,
            :height => _labelH
        });
        var bmp = ref.get();
        var bdc = bmp.getDc();
        bdc.setColor(Gfx.COLOR_TRANSPARENT, Gfx.COLOR_TRANSPARENT);
        bdc.clear();
        bdc.setColor(color, Gfx.COLOR_TRANSPARENT);
        bdc.drawText(_labelW / 2, _labelH / 2, font, text,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        return bmp;
    }

    // Blit one label so its baseline points outward along its radius.
    (:typecheck(false))
    function drawLabel(dc, idx) {
        var bmp = _labels[idx];
        if (bmp == null) { return; }

        var second = idx * 5;
        var angle = (second / 60.0) * 2.0 * Math.PI;

        // Position, then turn so the label reads outward, then shrink: XTINY is
        // the smallest built-in font, so SEC_LABEL_SCALE is how these get any
        // smaller than that.
        var t = new Gfx.AffineTransform();
        t.translate(_trackX[second] + _ox, _trackY[second] + _oy);
        t.rotate(angle);
        t.scale(SEC_LABEL_SCALE, SEC_LABEL_SCALE);
        t.translate(-_labelW / 2.0, -_labelH / 2.0);

        dc.drawBitmap2(0, 0, bmp, {
            :transform => t,
            :filterMode => Gfx.FILTER_MODE_BILINEAR
        });
    }

    // --- Second track: dots, numerals and comet -----------------------------

    (:typecheck(false))
    function drawSecondTrack(dc, sec, awake) {
        // The outer hour numerals share these same 12 marks, so they take the
        // spot over the ordinary 5-second labels rather than overlapping them.
        var hourOuter = Settings.showHourNumerals && Settings.hourNumeralsOuter;
        var showNumerals = Settings.showSecondNumerals && awake && _canRotate && !hourOuter;

        // Which track positions the comet is lighting, and in what colour.
        var trail = null;
        if (awake) { trail = cometColors(sec); }

        for (var i = 0; i < 60; i += 1) {
            var onFive = (i % 5 == 0);
            var hasNumeral = onFive && showNumerals;
            var lit = (trail != null) ? trail[i] : null;
            var x = _trackX[i] + _ox;
            var y = _trackY[i] + _oy;

            // CometOnFiveSec decides what the trail does at a mark that already
            // carries a numeral: off (the default) it skips it, so the tail
            // breaks around the numbers; on, it draws the ordinary small dot
            // there too and runs unbroken all the way round.
            if (hasNumeral && lit != null && !Settings.cometOnFiveSec) {
                lit = null;
            }

            var color;
            if (lit != null) {
                color = lit;
            } else if (onFive && !hasNumeral) {
                color = awake ? Theme.SEC_NUM_Q : Theme.TICK_DIM;
            } else {
                color = Theme.TICK_DIM;
            }

            var r = scaled((onFive && !hasNumeral) ? DOT_MAJOR : DOT_MINOR);
            if (!hasNumeral || lit != null) {
                dc.setColor(RainbowWave.tint(color, x, y), Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, r);
            }

            if (hasNumeral) { drawLabel(dc, i / 5); }
        }
    }

    // Colour for each of the 60 track positions, or null where the comet is not.
    (:typecheck(false))
    function cometColors(sec) {
        var out = new [60];
        for (var i = 0; i < 60; i += 1) { out[i] = null; }

        var mode = Settings.cometMode;

        if (mode == Settings.COMET_SPECTRUM_RING) {
            // The whole wheel is faintly present at all times.
            for (var j = 0; j < 60; j += 1) {
                out[j] = Theme.dim(Theme.hsvToColor(Theme.hueForSecond(j), 1.0, 1.0), 0.22);
            }
        }

        if (mode == Settings.COMET_CLASSIC) {
            // One hue for the whole tail, fading behind the head.
            var base = Theme.hsvToColor(Theme.hueForSecond(sec), 1.0, 1.0);
            var r = (base >> 16) & 0xFF;
            var g = (base >> 8) & 0xFF;
            var b = base & 0xFF;
            for (var k = 0; k < 8; k += 1) {
                var idx = ((sec - k) % 60 + 60) % 60;
                var alpha = 210 - k * 24;
                if (alpha < 20) { alpha = 20; }
                out[idx] = Gfx.createColor(alpha, r, g, b);
            }
            return out;
        }

        // Spectrum modes: every position owns a fixed hue, so the trail is a
        // scatter of colours from around the wheel rather than one tint. The
        // head lights at full brightness and the oldest dot goes out.
        for (var k2 = 0; k2 < 8; k2 += 1) {
            var idx2 = ((sec - k2) % 60 + 60) % 60;
            var f = 1.0 - (k2 / 8.0);
            out[idx2] = Theme.dim(
                Theme.hsvToColor(Theme.hueForSecond(idx2), 1.0, 1.0),
                0.25 + 0.75 * f);
        }
        return out;
    }

    // --- Hour marks ----------------------------------------------------------

    (:typecheck(false))
    function drawHourMarks(dc, awake) {
        if (!Settings.showHourNumerals) { return; }

        // HourNumeralsOuter moves the marks from the inner ring out to the
        // second track's radius, whichever style is drawing them.
        var outer = Settings.hourNumeralsOuter;
        var r = _radius * (outer ? R_SECOND : R_HOUR);

        if (Settings.hourMarkStyle == Settings.HOUR_MARK_NUMERALS) {
            drawHourNumerals(dc, awake, r, outer, false);
        } else if (Settings.hourMarkStyle == Settings.HOUR_MARK_LINES) {
            // 12/3/6/9 get the numeral; the other eight hours get a tick,
            // bold enough to read on its own since there's no numeral there.
            drawHourNumerals(dc, awake, r, outer, true);
            drawHourTicks(dc, awake, r, false, true);
        } else {
            drawHourTicks(dc, awake, r, true, false);
        }
    }

    // Numerals stay upright at every hour position (unlike the second-track
    // labels, which rotate to face outward). cardinalOnly restricts them to
    // 12/3/6/9, for the hybrid Lines style.
    (:typecheck(false))
    function drawHourNumerals(dc, awake, r, outer, cardinalOnly) {
        var font = outer ? HOUR_FONT_OUTER : HOUR_FONT;
        var base = awake ? Theme.NUMERAL : Theme.NUMERAL_DIM;
        var step = cardinalOnly ? 3 : 1;
        for (var h = step; h <= 12; h += step) {
            var a = (h / 12.0) * 2.0 * Math.PI;
            var x = _cx + r * Math.sin(a) + _ox;
            var y = _cy - r * Math.cos(a) + _oy;
            dc.setColor(RainbowWave.tint(base, x, y), Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, h.toString(),
                Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Radial ticks. cardinalOnly bolds and tints only 12/3/6/9, the other
    // eight hours getting a plain minor tick, for the cardinal-only style.
    // skipCardinal omits 12/3/6/9 entirely -- they carry a numeral instead --
    // and draws the remaining eight at the bold weight, for the hybrid Lines
    // style.
    (:typecheck(false))
    function drawHourTicks(dc, awake, r, cardinalOnly, skipCardinal) {
        var majorColor = awake ? Theme.HOUR_TICK_MAJOR : Theme.HOUR_TICK_MAJOR_DIM;
        var minorColor = awake ? Theme.HOUR_TICK_MINOR : Theme.HOUR_TICK_MINOR_DIM;

        for (var h = 1; h <= 12; h += 1) {
            var isCardinal = (h % 3 == 0);
            if (skipCardinal && isCardinal) { continue; }
            var isMajor = !cardinalOnly || isCardinal;
            var len = scaled(isMajor ? HOUR_TICK_MAJOR_LEN : HOUR_TICK_MINOR_LEN);
            var w   = scaled(isMajor ? Theme.HOUR_TICK_MAJOR_W
                                     : Theme.HOUR_TICK_MINOR_W);
            if (w < 1) { w = 1; }

            var a = (h / 12.0) * 2.0 * Math.PI;
            var sa = Math.sin(a);
            var ca = Math.cos(a);
            var x0 = _cx + (r - len / 2.0) * sa + _ox;
            var y0 = _cy - (r - len / 2.0) * ca + _oy;
            var x1 = _cx + (r + len / 2.0) * sa + _ox;
            var y1 = _cy - (r + len / 2.0) * ca + _oy;

            var color = isMajor
                ? RainbowWave.tint(majorColor, (x0 + x1) / 2, (y0 + y1) / 2)
                : minorColor;
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(w);
            dc.drawLine(x0, y0, x1, y1);
        }
        dc.setPenWidth(1);
    }

    // --- Orbit ring ---------------------------------------------------------

    (:typecheck(false))
    function drawOrbitRing(dc) {
        var r = _radius * R_ORBIT;
        var n = 72;
        for (var i = 0; i < n; i += 1) {
            var a = (i / (n * 1.0)) * 2.0 * Math.PI;
            var x = _cx + r * Math.sin(a) + _ox;
            var y = _cy - r * Math.cos(a) + _oy;
            dc.setColor(RainbowWave.tint(Theme.ORBIT_RING, x, y), Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 1);
        }
    }

    // --- Background: starfield or zodiac ------------------------------------

    (:typecheck(false))
    function drawBackground(dc, sec) {
        var mode = Settings.background;
        if (mode == Settings.BG_STARFIELD) {
            drawStarfield(dc, sec);
        } else {
            drawZodiac(dc, sec, mode == Settings.BG_ZODIAC_LINES);
        }
    }

    // Deterministic pseudo-random field: the same stars every boot, but denser
    // and more varied than a hand-written list, and it scales with density.
    (:typecheck(false))
    function buildStars() {
        var counts = [0, 14, 28, 44];
        var n = counts[Settings.starDensity];
        _stars = new [n * 4];

        var seed = 20260822;
        for (var i = 0; i < n; i += 1) {
            seed = (seed * 75 + 74) % 65537;
            var u = seed / 65537.0;
            seed = (seed * 75 + 74) % 65537;
            var v = seed / 65537.0;
            seed = (seed * 75 + 74) % 65537;
            var w = seed / 65537.0;

            // sqrt for uniform area density; kept clear of the hub and the rim.
            var rr = _radius * (0.20 + 0.66 * Math.sqrt(u));
            var aa = v * 2.0 * Math.PI;

            var tier = 0;
            if (w > 0.92)      { tier = 2; }
            else if (w > 0.70) { tier = 1; }

            _stars[i * 4]     = _cx + rr * Math.sin(aa);
            _stars[i * 4 + 1] = _cy - rr * Math.cos(aa);
            _stars[i * 4 + 2] = tier;
            _stars[i * 4 + 3] = 0.55 + 0.45 * w;
        }
    }

    (:typecheck(false))
    function drawStarfield(dc, sec) {
        if (_stars == null) { return; }
        var n = _stars.size() / 4;
        for (var i = 0; i < n; i += 1) {
            drawStar(dc, _stars[i * 4] + _ox, _stars[i * 4 + 1] + _oy,
                _stars[i * 4 + 2], _stars[i * 4 + 3], sec, i);
        }
    }

    // Three sizes of sprite so the field has depth instead of reading as a
    // uniform scatter of pixels.
    (:typecheck(false))
    function drawStar(dc, x, y, tier, bright, sec, index) {
        var b = bright;
        // A few of the brightest pulse on the free 1 Hz redraw.
        if (tier == 2) {
            var phase = ((sec + index * 7) % 8) / 8.0;
            b = b * (0.72 + 0.28 * Math.sin(phase * 2.0 * Math.PI));
        }

        var base = (tier == 2) ? Theme.STAR_BRIGHT
                 : (tier == 1) ? Theme.STAR : Theme.STAR;
        var color = RainbowWave.tint(Theme.dim(base, b), x, y);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);

        if (tier == 0) {
            dc.fillCircle(x, y, 1);
            return;
        }

        var arm = (tier == 2) ? scaled(3) : scaled(2);
        dc.setPenWidth(1);
        dc.drawLine(x - arm, y, x + arm, y);
        dc.drawLine(x, y - arm, x, y + arm);
        dc.fillCircle(x, y, (tier == 2) ? 2 : 1);

        if (tier == 2) {
            // Faint diagonals give the four-point sparkle its body.
            var d = (arm * 0.55).toNumber();
            dc.setColor(Theme.dim(color, 0.45), Gfx.COLOR_TRANSPARENT);
            dc.drawLine(x - d, y - d, x + d, y + d);
            dc.drawLine(x - d, y + d, x + d, y - d);
        }
    }

    // Zodiac constellation: the principal stars, optionally joined by lines.
    // No glyphs, no figures -- just the star pattern.
    (:typecheck(false))
    function drawZodiac(dc, sec, withLines) {
        var sign = Settings.zodiacSign;
        if (sign == 0) { sign = Zodiac.currentSign(); }

        if (sign != _zodiacSign) {
            buildZodiac(sign);
            _zodiacSign = sign;
        }
        if (_zodiacPts == null) { return; }

        var n = _zodiacPts.size() / 3;

        if (withLines) {
            var pairs = Zodiac.lines(sign);
            dc.setPenWidth(1);
            for (var i = 0; i + 1 < pairs.size(); i += 2) {
                var a = pairs[i];
                var b = pairs[i + 1];
                if (a >= n || b >= n) { continue; }
                var ax = _zodiacPts[a * 3] + _ox;
                var ay = _zodiacPts[a * 3 + 1] + _oy;
                var bx = _zodiacPts[b * 3] + _ox;
                var by = _zodiacPts[b * 3 + 1] + _oy;
                dc.setColor(
                    RainbowWave.tint(Theme.ZODIAC_LINE, (ax + bx) / 2, (ay + by) / 2),
                    Gfx.COLOR_TRANSPARENT);
                dc.drawLine(ax, ay, bx, by);
            }
        }

        for (var j = 0; j < n; j += 1) {
            drawStar(dc, _zodiacPts[j * 3] + _ox, _zodiacPts[j * 3 + 1] + _oy,
                _zodiacPts[j * 3 + 2], 1.0, sec, j);
        }
    }

    // Fit the chosen pattern to the dial. Done on sign change only, so the
    // constellation data can stay in whatever coordinates read clearly in
    // source rather than being pre-normalised.
    (:typecheck(false))
    function buildZodiac(sign) {
        var src = Zodiac.stars(sign);
        var n = src.size() / 3;
        if (n == 0) { _zodiacPts = null; return; }

        var minX = src[0]; var maxX = src[0];
        var minY = src[1]; var maxY = src[1];
        for (var i = 1; i < n; i += 1) {
            var x = src[i * 3];
            var y = src[i * 3 + 1];
            if (x < minX) { minX = x; }
            if (x > maxX) { maxX = x; }
            if (y < minY) { minY = y; }
            if (y > maxY) { maxY = y; }
        }

        var spanX = maxX - minX;
        var spanY = maxY - minY;
        if (spanX < 0.01) { spanX = 0.01; }
        if (spanY < 0.01) { spanY = 0.01; }

        // Fit inside the hour numerals, and sit a little high so the busiest
        // part of a pattern clears the moon subdial at the bottom.
        var extent = _radius * 1.30;
        var k = extent / spanX;
        var ky = extent / spanY;
        if (ky < k) { k = ky; }

        var midX = (minX + maxX) / 2.0;
        var midY = (minY + maxY) / 2.0;
        var offY = -_radius * 0.08;

        _zodiacPts = new [n * 3];
        for (var j = 0; j < n; j += 1) {
            _zodiacPts[j * 3]     = _cx + (src[j * 3] - midX) * k;
            _zodiacPts[j * 3 + 1] = _cy + (src[j * 3 + 1] - midY) * k + offY;
            _zodiacPts[j * 3 + 2] = Zodiac.tierFor(src[j * 3 + 2]);
        }
    }
}
