using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Application;

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

    // --- Starfield: the Milky Way band ---------------------------------------
    // The field is two populations: a dense band arcing across the dial, and a
    // sparse scatter over the rest of it. The band is fixed - it does not turn
    // with the time - and it is bowed rather than straight, which is what makes
    // it read as the Milky Way instead of as a stripe.
    const MW_ANGLE = 0.52;      // band axis, radians clockwise from vertical
    const MW_BOW   = 0.55;      // how far the arc bows; 0 would be a straight band
    const MW_WIDTH = 0.30;      // half-width either side of the spine, in radius units
    const MW_SHARE = 0.62;      // fraction of stars belonging to the band
    const MW_SPAN  = 0.86;      // band reaches this fraction of the radius

    // Stars keep clear of the hub, where the hands and the moon live, and of
    // the rim, where the second track runs.
    const STAR_R_MIN = 0.20;
    const STAR_R_MAX = 0.86;

    // --- Starfield: moonlight ------------------------------------------------
    // Moonlight washes stars out, so the sky doubles as a second reading of the
    // phase the moon disc shows. Three things move together, because a cutoff
    // on its own only makes the field sparser and the survivors - which are the
    // brightest, most conspicuous sprites - stay exactly as loud as they were:
    //
    //   MOON_FLOOR      faintest magnitude still visible at full moon.
    //                   Everything below it is skipped.
    //   MOON_WASH       how much of its brightness the whole field loses by
    //                   full moon, on top of the cutoff. This is what stops a
    //                   full moon reading as "the same stars, fewer of them".
    //   STAR_LEVEL_MIN  how brightly a star draws when it is right at the
    //                   cutoff, so stars fade out instead of popping.
    const MOON_FLOOR     = 0.88;
    const MOON_WASH      = 0.45;
    const STAR_LEVEL_MIN = 0.55;

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

    var _stars = null;          // flat: x, y, tier, magnitude
    var _zodiacSign = -1;
    var _zodiacPts = null;      // flat: x, y, tier

    // Pre-drawn sprites for the bright star tiers, and the options dictionary
    // drawBitmap2 takes. The dictionary is reused and its :tintColor rewritten
    // per star rather than allocated per call - a few hundred short-lived
    // dictionaries a second is churn the field does not need.
    var _star3 = null;          // tier 0
    var _star5 = null;          // tier 1
    var _star7 = null;          // tier 2 and 3
    var _tintOpt = null;
    var _canTint = false;

    (:typecheck(false))
    function setup(dc, cx, cy, radius, scale) {
        _cx = cx;
        _cy = cy;
        _radius = radius;
        _scale = scale;
        _canRotate = (dc has :drawBitmap2);

        // Loaded once here rather than lazily on the draw path. They live in
        // the graphics pool, not the app heap, so they cost nothing against
        // the 128kB budget the field's arrays come out of.
        //
        // Hold the resource, not the ResourceReference. The pool unloads and
        // reloads references behind your back as memory moves, so a bare
        // reference makes every drawBitmap2 pay a pool resolve - invisible on
        // the simulator, expensive on the watch. get() locks it, which for two
        // sprites of <=7x7 costs nothing. Same pattern as renderLabel below
        // and MoonDial.mc:107.
        _canTint = (dc has :drawBitmap2);
        if (_canTint) {
            _star3 = lockedBitmap(Rez.Drawables.Star3);
            _star5 = lockedBitmap(Rez.Drawables.Star5);
            _star7 = lockedBitmap(Rez.Drawables.Star7);
            _tintOpt = { :tintColor => Theme.STAR };
        }

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

    // A bitmap resource locked into the graphics pool. loadResource hands back
    // a ResourceReference on this API level; keeping only the reference lets
    // the pool purge and reload the bitmap underneath you. The has-check is
    // for the case where the resource comes back directly.
    (:typecheck(false))
    function lockedBitmap(res) {
        var ref = Application.loadResource(res);
        return (ref has :get) ? ref.get() : ref;
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
        var x = _trackX[second] + _ox;
        var y = _trackY[second] + _oy;

        var t = new Gfx.AffineTransform();
        t.translate(x, y);
        t.rotate(angle);
        t.scale(SEC_LABEL_SCALE, SEC_LABEL_SCALE);
        t.translate(-_labelW / 2.0, -_labelH / 2.0);

        // The label's colour is baked into the bitmap, so the rainbow wave
        // cannot blend it the way tint() does elsewhere -- :tintColor repaints
        // the glyph wholesale instead, which at this size reads the same.
        var wave = RainbowWave.tintColor(x, y);
        if (wave == null) {
            dc.drawBitmap2(0, 0, bmp, {
                :transform => t,
                :filterMode => Gfx.FILTER_MODE_BILINEAR
            });
        } else {
            dc.drawBitmap2(0, 0, bmp, {
                :transform => t,
                :filterMode => Gfx.FILTER_MODE_BILINEAR,
                :tintColor => wave
            });
        }
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

        // Only two dot sizes exist, so scale them once rather than sixty times.
        var rMajor = scaled(DOT_MAJOR);
        var rMinor = scaled(DOT_MINOR);

        // The colour currently on the Dc, so a run of same-coloured dots pays
        // for one setColor rather than one each. Null means "unknown": nothing
        // in this module can assume what the previous section left behind.
        var last = null;

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

            var r = (onFive && !hasNumeral) ? rMajor : rMinor;
            if (!hasNumeral || lit != null) {
                // Most of the ring is one colour: everything the comet is not
                // lighting is TICK_DIM, and in low power - comet off, numerals
                // hidden - that is all sixty positions. Setting the colour only
                // where it actually changes takes the ring from sixty setColor
                // calls to one, and from forty-eight to a dozen or so awake.
                // The wave is the exception: it gives every position a colour
                // of its own, and there the check simply never fires.
                var want = RainbowWave.tint(color, x, y);
                if (want != last) {
                    dc.setColor(want, Gfx.COLOR_TRANSPARENT);
                    last = want;
                }
                dc.fillCircle(x, y, r);
            }

            if (hasNumeral) { drawLabel(dc, i / 5); }
        }
    }

    // Every track position owns a fixed hue, so the sixty HSV conversions
    // behind the wheel are a constant table, not per-frame work. hsvToColor is
    // a dozen float operations and three roundings, and the spectrum ring mode
    // was running it once per position per second for an answer that never
    // changes. The resting ring is dimmed once here too.
    var _wheel = null;          // full-brightness hue per track position
    var _wheelRing = null;      // the same wheel at the ring's resting dimness
    var _comet = null;          // scratch trail, reused so a frame allocates none

    (:typecheck(false))
    function buildWheel() {
        _wheel = new [60];
        _wheelRing = new [60];
        _comet = new [60];
        for (var i = 0; i < 60; i += 1) {
            _wheel[i] = Theme.hsvToColor(Theme.hueForSecond(i), 1.0, 1.0);
            _wheelRing[i] = Theme.dim(_wheel[i], 0.22);
        }
    }

    // Colour for each of the 60 track positions, or null where the comet is not.
    (:typecheck(false))
    function cometColors(sec) {
        if (_wheel == null) { buildWheel(); }

        var out = _comet;
        var mode = Settings.cometMode;

        if (mode == Settings.COMET_SPECTRUM_RING) {
            // The whole wheel is faintly present at all times, so every
            // position gets written and there is nothing to clear first.
            for (var j = 0; j < 60; j += 1) { out[j] = _wheelRing[j]; }
        } else {
            for (var i = 0; i < 60; i += 1) { out[i] = null; }
        }

        if (mode == Settings.COMET_CLASSIC) {
            // One hue for the whole tail, fading behind the head.
            var base = _wheel[sec % 60];
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
            out[idx2] = Theme.dim(_wheel[idx2], 0.25 + 0.75 * f);
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

    // Radial ticks. cardinalOnly bolds only 12/3/6/9, the other eight hours
    // getting a plain minor tick, for the cardinal-only style. skipCardinal
    // omits 12/3/6/9 entirely -- they carry a numeral instead -- and draws the
    // remaining eight at the bold weight, for the hybrid Lines style.
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

            var color = RainbowWave.tint(isMajor ? majorColor : minorColor,
                (x0 + x1) / 2, (y0 + y1) / 2);
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(w);
            dc.drawLine(x0, y0, x1, y1);
        }
        dc.setPenWidth(1);
    }

    // --- Orbit ring ---------------------------------------------------------

    // Left out of the rainbow wave: it is ornament rather than a mark, and a
    // lit ring competes with the second track the wave is crossing.
    (:typecheck(false))
    function drawOrbitRing(dc) {
        var r = _radius * R_ORBIT;
        var n = 72;
        dc.setColor(Theme.ORBIT_RING, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i += 1) {
            var a = (i / (n * 1.0)) * 2.0 * Math.PI;
            var x = _cx + r * Math.sin(a) + _ox;
            var y = _cy - r * Math.cos(a) + _oy;
            dc.fillCircle(x, y, 1);
        }
    }

    // --- Background: starfield or zodiac ------------------------------------

    // frac is the moon phase, 0..1. Only the starfield uses it; the zodiac
    // patterns are an informational display and stay fully lit at every phase,
    // since fading them by magnitude would break the constellation shapes.
    (:typecheck(false))
    function drawBackground(dc, sec, frac) {
        var mode = Settings.background;
        if (mode == Settings.BG_STARFIELD) {
            drawStarfield(dc, sec, frac);
        } else {
            drawZodiac(dc, sec, mode == Settings.BG_ZODIAC_LINES);
        }
    }

    // Deterministic pseudo-random field: the same sky every boot, drawn from
    // two populations - the Milky Way band, and a sparse scatter over the rest
    // of the dial.
    //
    // Band membership is decided per star rather than by splitting the array,
    // so star i is the same star at every count: raising StarCount adds stars
    // without moving the ones already there.
    //
    // This runs on setup and on a StarCount change, never on the draw path, so
    // the sqrt and the resampling below cost nothing per frame.
    (:typecheck(false))
    function buildStars() {
        var n = Settings.starCount;
        _stars = new [n * 4];
        _starColors = null;
        _starOrder = null;
        if (n <= 0) { return; }

        var ca = Math.cos(MW_ANGLE);
        var sa = Math.sin(MW_ANGLE);

        var bright = 0;         // bright stars so far, for the twinkle gate
        var seed = 20260822;
        for (var i = 0; i < n; i += 1) {
            seed = (seed * 75 + 74) % 65537;
            var c = seed / 65537.0;             // band or field
            var inBand = (c < MW_SHARE);

            // Position. A band point can fall in the hub or past the rim, so it
            // gets a few more tries before being clamped into range; clamping is
            // rare enough not to show as a line of stars on the boundary.
            var ux = 0.0;
            var uy = 0.0;
            var rr = 0.0;
            for (var attempt = 0; attempt < 5; attempt += 1) {
                seed = (seed * 75 + 74) % 65537;
                var u = seed / 65537.0;
                seed = (seed * 75 + 74) % 65537;
                var v = seed / 65537.0;
                seed = (seed * 75 + 74) % 65537;
                var v2 = seed / 65537.0;

                if (inBand) {
                    // s runs along the band, d across it. Two uniforms summed
                    // give a triangular spread, so the band is dense on its
                    // spine and thins out to either side. The bow term is what
                    // curves the spine into an arc rather than a straight line.
                    var s = -1.0 + 2.0 * u;
                    var d = MW_WIDTH * (v + v2 - 1.0);
                    var t = MW_BOW * (s * s - 0.5) + d;
                    ux = (s * ca - t * sa) * MW_SPAN;
                    uy = (s * sa + t * ca) * MW_SPAN;
                } else {
                    // sqrt for uniform area density.
                    var fr = STAR_R_MIN
                           + (STAR_R_MAX - STAR_R_MIN) * Math.sqrt(u);
                    var aa = v * 2.0 * Math.PI;
                    ux = fr * Math.sin(aa);
                    uy = -fr * Math.cos(aa);
                }

                rr = Math.sqrt(ux * ux + uy * uy);
                if (rr >= STAR_R_MIN && rr <= STAR_R_MAX) { break; }
            }

            if (rr < 0.0001) {
                ux = STAR_R_MIN;
                uy = 0.0;
            } else if (rr < STAR_R_MIN || rr > STAR_R_MAX) {
                var target = (rr < STAR_R_MIN) ? STAR_R_MIN : STAR_R_MAX;
                var k = target / rr;
                ux = ux * k;
                uy = uy * k;
            }

            seed = (seed * 75 + 74) % 65537;
            var w = seed / 65537.0;             // magnitude within its class
            seed = (seed * 75 + 74) % 65537;
            var w2 = seed / 65537.0;            // which class

            // Magnitude spans a wide range with far more faint stars than
            // bright, which is what makes the moonlight fade legible: the band
            // is mostly haze that vanishes early. The faint floors sit close to
            // zero so the dimmest stars start going as soon as there is any
            // moon at all, rather than surviving the first week intact. Both
            // populations keep a small bright minority, so a full moon does not
            // leave an obvious hole where the band was.
            var mag;
            if (inBand) {
                mag = (w2 > 0.90) ? 0.78 + 0.22 * w
                                  : 0.04 + 0.62 * w * w * w;
            } else {
                mag = (w2 > 0.72) ? 0.72 + 0.28 * w
                                  : 0.18 + 0.54 * w * w;
            }

            // Sprite size follows magnitude rather than being rolled
            // separately, so a big sprite always means a bright star. Tier 3 is
            // tier 2 that also twinkles - see drawStar.
            //
            // Every third bright star twinkles, counted rather than drawn from
            // the LCG. Two reasons: w2 has already been spent deciding which
            // magnitude branch this star took, so reusing it would make every
            // bright star a twinkler and leave tier 2 unreachable; and a fresh
            // draw is no good either, because this generator sampled at a fixed
            // stride per star is correlated enough that a threshold of 1/3 came
            // out at 2/3 in practice. A counter pins the number of moving stars
            // exactly, which is the point of the gate.
            var tier = 0;
            if (mag >= 0.85) {
                tier = (bright % 3 == 0) ? 3 : 2;
                bright += 1;
            } else if (mag >= 0.62) {
                tier = 1;
            }

            // Rounded to whole pixels here rather than per frame: these are
            // screen coordinates, and drawPoint wants a Number.
            _stars[i * 4]     = (_cx + ux * _radius + 0.5).toNumber();
            _stars[i * 4 + 1] = (_cy + uy * _radius + 0.5).toNumber();
            _stars[i * 4 + 2] = tier;
            _stars[i * 4 + 3] = mag;
        }
    }

    (:typecheck(false))
    function drawStarfield(dc, sec, frac) {
        if (_stars == null) { return; }
        var n = _stars.size() / 4;
        if (n <= 0) { return; }

        // Moonlight raises the faintest magnitude that still shows: nothing at
        // new moon, most of the field by full. Stars under the cutoff are
        // skipped before any Dc call, so a full moon is also the cheapest frame.
        var illum = MoonPhase.illumination(frac);
        var floorMag = MOON_FLOOR * illum;
        var span = 1.0 - floorMag;

        // The cutoff alone leaves the brightest stars burning at full strength
        // through every phase, so the field reads as the same sky with gaps in
        // it. Dimming what survives as well is what makes a full moon look
        // washed out rather than merely sparse.
        var wash = 1.0 - MOON_WASH * illum;

        // Everything above depends only on the moon's illumination, which
        // moves over days, so the finished colour of every star is cached and
        // rebuilt a handful of times a day rather than recomputed for each of
        // several hundred stars, every second. See STAR_COLOUR_CACHE.
        var bucket = (illum * ILLUM_STEPS).toNumber();
        if (_starColors == null || _starColorKey[0] != bucket
                || _starColorKey[1] != n) {
            buildStarColors(n, floorMag, span, wash);
            _starColorKey = [bucket, n];
        }
        if (_starOrder == null || _starOrder.size() == 0) { return; }

        // A crossing wave recolours by position and changes every frame, so
        // there is nothing to cache for the few seconds it is up.
        var waveOn = RainbowWave.isActive();

        // These sprites are one to three pixels across; there is nothing here
        // for antialiasing to smooth, and switching it off makes a hundred-odd
        // tiny fills markedly cheaper. Restored before anything else draws.
        var aa = (dc has :setAntiAlias);
        if (aa) { dc.setAntiAlias(false); }

        // Every sprite strokes at one pixel, so the pen is set for the whole
        // field instead of once per star.
        dc.setPenWidth(1);

        // _starOrder holds only the stars above the cutoff, grouped by colour,
        // so the loop neither tests the cutoff nor repeats a setColor within a
        // group. cur is the colour currently on the Dc; -1 is never a colour.
        var order = _starOrder;
        var m = order.size();
        var cur = -1;

        for (var k = 0; k < m; k += 1) {
            var i = order[k];
            var tier = _stars[i * 4 + 2];
            var x = _stars[i * 4] + _ox;
            var y = _stars[i * 4 + 1] + _oy;

            if (tier == 3 || waveOn) {
                // Tier 3 pulses on the second; neither it nor a live wave
                // survives a cache, so these take the long way round - and
                // they leave a colour of their own behind.
                drawStar(dc, x, y, tier, starLevel(i, floorMag, span, wash),
                    sec, i, starBase(tier), true);
                cur = -1;
                continue;
            }

            var color = _starColors[i];
            if (color != cur) {
                dc.setColor(color, Gfx.COLOR_TRANSPARENT);
                cur = color;
            }
            drawStarSprite(dc, x, y, tier, color, true);

            // A sparkle used to dim the Dc for its diagonals without restoring
            // it, which broke the colour run here. Now that the diagonals are
            // baked into the tinted sprite nothing touches the Dc colour, so
            // the run carries on - but the stroke fallback still does dim it.
            if (tier >= 2 && !_canTint) { cur = -1; }
        }

        if (aa) { dc.setAntiAlias(true); }
    }

    // --- STAR_COLOUR_CACHE ---------------------------------------------------
    //
    // The moon subdial caches its whole rendering into a bitmap; the starfield
    // cannot. A background bitmap would have to be the full 454x454, which
    // does not fit in the 128kB a watch face gets at any bit depth worth
    // having. So the saving comes from the per-star work instead: the fade
    // level and the Theme.dim that turns it into a colour are the expensive
    // part, and both are functions of the illumination alone.
    //
    // ILLUM_STEPS buckets across a lunation works out at a few rebuilds a day.
    const ILLUM_STEPS = 64;

    // Brightness steps the fade is quantised to before it becomes a colour.
    // starLevel is continuous in magnitude, so ungrouped every star ends up
    // with a colour of its own and the draw loop pays a setColor for each one.
    // Ten steps is indistinguishable across sprites one to five pixels wide,
    // and it collapses a couple of hundred colour changes a frame into a
    // couple of dozen. See _starOrder.
    const LEVEL_STEPS = 10;

    var _starColors = null;
    var _starColorKey = null;   // [illumination bucket, star count]

    // Indices of the stars above the cutoff, grouped so equal colours are
    // adjacent. Built with the colour cache, walked instead of the raw array.
    var _starOrder = null;

    // Fade in from black as a star clears the cutoff, so stars dissolve over
    // several nights instead of popping in and out.
    (:typecheck(false))
    function starLevel(i, floorMag, span, wash) {
        var mag = _stars[i * 4 + 3];
        return wash * (STAR_LEVEL_MIN
             + (1.0 - STAR_LEVEL_MIN) * ((mag - floorMag) / span));
    }

    (:typecheck(false))
    function starBase(tier) {
        return (tier >= 2) ? Theme.STAR_BRIGHT
             : (tier == 1) ? Theme.STAR
             : Theme.STAR_DIM;
    }

    // Colours for the whole field, plus the order to draw them in. Runs on an
    // illumination bucket change, a few times a day, never on the draw path.
    //
    // The order is a counting sort into (tier, brightness step) buckets, so
    // the draw loop walks the field colour by colour and sets each colour
    // once. Tier is part of the key because it picks the base colour; keying
    // it first also puts the twinkling tier last, where its per-star recolour
    // cannot split a run.
    (:typecheck(false))
    function buildStarColors(n, floorMag, span, wash) {
        _starColors = new [n];

        var buckets = 4 * LEVEL_STEPS;
        var counts = new [buckets];
        for (var b = 0; b < buckets; b += 1) { counts[b] = 0; }

        var keys = new [n];
        var visible = 0;

        for (var i = 0; i < n; i += 1) {
            var mag = _stars[i * 4 + 3];
            if (mag <= floorMag) {
                _starColors[i] = null;      // under the cutoff: not drawn
                keys[i] = -1;
                continue;
            }

            var step = (((mag - floorMag) / span) * LEVEL_STEPS).toNumber();
            if (step < 0) { step = 0; }
            if (step > LEVEL_STEPS - 1) { step = LEVEL_STEPS - 1; }

            // The step's midpoint, so quantising does not bias the field dark.
            var tier = _stars[i * 4 + 2];
            var level = wash * (STAR_LEVEL_MIN + (1.0 - STAR_LEVEL_MIN)
                      * ((step + 0.5) / LEVEL_STEPS));
            _starColors[i] = Theme.dim(starBase(tier), level);

            var key = tier * LEVEL_STEPS + step;
            keys[i] = key;
            counts[key] += 1;
            visible += 1;
        }

        var offsets = new [buckets];
        var run = 0;
        for (var b2 = 0; b2 < buckets; b2 += 1) {
            offsets[b2] = run;
            run += counts[b2];
        }

        _starOrder = new [visible];
        for (var j = 0; j < n; j += 1) {
            var k = keys[j];
            if (k < 0) { continue; }
            _starOrder[offsets[k]] = j;
            offsets[k] += 1;
        }
    }

    // Three sizes of sprite so the field has depth instead of reading as a
    // uniform scatter of pixels. Tiers: 0 a three-pixel cross, 1 a larger cross
    // with a centre dot, 2 a four-point sparkle, 3 the same sparkle but
    // twinkling.
    //
    // base is passed in rather than derived from the tier, because the two
    // callers want different palettes: the starfield fades its faintest stars
    // to STAR_DIM, while the zodiac keeps every constellation star legible.
    (:typecheck(false))
    function drawStar(dc, x, y, tier, bright, sec, index, base, sprite) {
        var b = bright;
        // Only tier 3 pulses, on the free 1 Hz redraw, offset per star so they
        // are not in lockstep. Gating it to its own tier keeps the number of
        // twinklers at a handful however large the field grows - and stops the
        // whole sky shimmering at full moon, when the survivors are all bright.
        if (tier == 3) {
            var phase = ((sec + index * 7) % 8) / 8.0;
            b = b * (0.72 + 0.28 * Math.sin(phase * 2.0 * Math.PI));
        }

        drawStarShape(dc, x, y, tier, RainbowWave.tint(Theme.dim(base, b), x, y),
            sprite);
    }

    // The sprite itself, given a finished colour. Split out so the starfield's
    // cache can skip straight to it; drawStar is still the way in for anything
    // that has to derive the colour first.
    (:typecheck(false))
    function drawStarShape(dc, x, y, tier, color, sprite) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        drawStarSprite(dc, x, y, tier, color, sprite);
    }

    // The sprite alone, with the colour and the pen width already on the Dc.
    // Every Dc call is a VM-to-native crossing and they dominate the field's
    // cost - at 200 stars the setColor and setPenWidth the old shape did per
    // star were together about four calls in every ten. drawStarfield now sets
    // the pen once for the whole field and the colour once per colour run, and
    // comes here for the shape.
    //
    // Not every Dc call costs the same, which is what the tier split below
    // turns on: a drawLine is ~6us and a fillCircle ~126us. See below and
    // docs/starfield-perf.md.
    (:typecheck(false))
    function drawStarSprite(dc, x, y, tier, color, sprite) {
        if (tier == 0) {
            // A three-pixel cross, not a lone pixel. Colour alone could not
            // rescue the faint tier: a 1x1 sprite on an AMOLED black is under
            // the size the eye resolves at any brightness the moonlight fade
            // leaves it, so most of a 200-star field simply was not there to
            // be counted. Five pixels is still unmistakably the smallest
            // sprite - tier 1 is a longer cross with a filled centre.
            //
            // The cross is now one blit rather than two strokes, which is the
            // single largest saving on the frame: this tier is 78% of the
            // field and was 312 of its 356 draw calls.
            //
            // It was left as strokes for a long time on the strength of a
            // benchmark reading ~6us a stroke against ~39us a blit. That arm
            // had been run with anti-aliasing off, and onUpdate turns it on
            // for the whole frame; re-timed in the state the field actually
            // draws in, a stroke is 85us. Measured again on the watch itself,
            // a Venu 3 charges per Dc call and barely distinguishes the
            // primitives at all - 3px stroke 1.00, fillCircle 1.16, blit 1.17
            // - so two strokes cost 2.00 against the blit's 1.17. See
            // docs/track-perf.md.
            //
            // A single three-pixel dash would be cheaper still, and remains
            // rejected: a field of dashes reads as scratches rather than
            // stars, whether they all lie the same way or alternate.
            //
            // The sprite is the same five lit pixels the strokes drew, so this
            // is a cost change and not a look change. It is opaque black
            // outside the cross, so it is only safe where nothing is
            // underneath - hence the same `sprite` flag the bright tiers use,
            // false from drawZodiac, which lays its joining lines down first.
            if (sprite && _canTint) {
                _tintOpt[:tintColor] = color;
                dc.drawBitmap2(x - 1, y - 1, _star3, _tintOpt);
                return;
            }
            dc.drawLine(x - 1, y, x + 1, y);
            dc.drawLine(x, y - 1, x, y + 1);
            return;
        }

        // Tiers 1 and up are a single tinted blit. Each used to be a
        // fillCircle plus two to four strokes, and a fillCircle is by a long
        // way the most expensive primitive in this module: benchmarked on a
        // Venu 3 simulator at 126us against 6.4us for a drawLine - 20x a
        // stroke, and 3x an entire drawBitmap2. It was ~90% of what these
        // sprites cost.
        //
        //   tier 1   139us of strokes and a circle  ->  44us as one blit
        //   tier 2/3 165us                          ->  43us
        //
        // A blit's cost is per-call, not per-pixel: 3x3, 5x5 and 7x7 all
        // timed within noise of each other. That is also why tier 0 above
        // stays as two strokes - at 13us it is already cheaper than the ~39us
        // any blit costs, so a sprite there is a 3x loss. It is 78% of the
        // field, so getting that half of the split wrong would undo all of
        // this. See docs/starfield-perf.md.
        //
        // sprite is false where something is already drawn underneath - the
        // zodiac's joining lines - because the sprites are opaque black
        // outside the star and would erase it. See drawZodiac.
        //
        // :tintColor scales the grayscale source by the star's colour, which
        // is what folds the sparkle's dim diagonals into the same call: they
        // are baked into the sprite at 45% grey instead of costing a setColor
        // and two more strokes.
        if (sprite && _canTint) {
            _tintOpt[:tintColor] = color;
            if (tier == 1) {
                dc.drawBitmap2(x - 2, y - 2, _star5, _tintOpt);
            } else {
                dc.drawBitmap2(x - 3, y - 3, _star7, _tintOpt);
            }
            return;
        }

        var big = (tier >= 2);
        var arm = big ? scaled(3) : scaled(2);
        dc.drawLine(x - arm, y, x + arm, y);
        dc.drawLine(x, y - arm, x, y + arm);
        dc.fillCircle(x, y, big ? 2 : 1);

        if (big) {
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

        // The joining lines sit out the rainbow wave; only the stars themselves
        // light up, so the constellation keeps its shape as the band crosses.
        if (withLines) {
            var pairs = Zodiac.lines(sign);
            dc.setPenWidth(1);
            dc.setColor(Theme.ZODIAC_LINE, Gfx.COLOR_TRANSPARENT);
            for (var i = 0; i + 1 < pairs.size(); i += 2) {
                var a = pairs[i];
                var b = pairs[i + 1];
                if (a >= n || b >= n) { continue; }
                var ax = _zodiacPts[a * 3] + _ox;
                var ay = _zodiacPts[a * 3 + 1] + _oy;
                var bx = _zodiacPts[b * 3] + _ox;
                var by = _zodiacPts[b * 3 + 1] + _oy;
                dc.drawLine(ax, ay, bx, by);
            }
        }

        // Full brightness at every phase, and the old two-colour palette: a
        // constellation has to keep its shape, so the moonlight rules and the
        // faint STAR_DIM tier that the starfield uses both stay out of here.
        // Zodiac tier 2 is promoted to 3 so its bright stars still twinkle, as
        // they did when tier 2 alone carried the pulse.
        for (var j = 0; j < n; j += 1) {
            var ztier = _zodiacPts[j * 3 + 2];
            var zbase = (ztier >= 2) ? Theme.STAR_BRIGHT : Theme.STAR;
            if (ztier == 2) { ztier = 3; }
            // sprite = false: the joining lines are already on the Dc and the
            // sprites are opaque black outside the star, so blitting one over
            // a line erases the couple of pixels where they meet. The zodiac
            // is a dozen stars - the strokes it costs are not worth a visible
            // notch in every line. Nothing is ever underneath a starfield
            // star, which is why that path can use the sprites.
            drawStar(dc, _zodiacPts[j * 3] + _ox, _zodiacPts[j * 3 + 1] + _oy,
                ztier, 1.0, sec, j, zbase, false);
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
