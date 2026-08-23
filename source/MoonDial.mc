using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Lang;

// The moon subdial.
//
// Shaded as a sphere rather than a flat cut-out. Each row of the disc is walked
// horizontally and the surface normal at that point gives a Lambert term, so the
// terminator falls off as a gradient instead of a hard edge, and the limb darkens
// the way a real moon does. The maria are part of the same ramp, so they shade
// with the surface instead of sitting on top of it as flat patches.
//
// The same geometry renders an eclipse: a lunar eclipse is a fully lit disc in
// a copper palette, a solar eclipse is an occulted disc with a corona.
module MoonDial {

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

    // Shading is a continuous ramp rather than a few flat bands. The disc is
    // walked in horizontal steps; at each step the surface normal of the sphere
    // gives a Lambert term (which produces the terminator falloff for free) and
    // the z component gives limb darkening. The result is quantised into LEVELS
    // tones and drawn as runs, so a smooth gradient still costs only a handful
    // of drawLine calls per scanline.
    const LEVELS = 18;          // tones in the ramp; raise for smoother, slower
    const STEP_PX = 3;          // horizontal sampling step, pixels
    const AMBIENT = 0.06;       // floor so the lit side never goes fully black
    const LIMB_FLOOR = 0.42;    // brightness at the very limb, 1.0 = no darkening

    // How wide the lit crescent has to be before the bright rim on the lit limb
    // reaches full strength, as a fraction of the disc's width. Below it the rim
    // fades out, so a new moon is a genuinely dark disc rather than a dark disc
    // with a hairline crescent drawn round it.
    const RIM_FADE = 0.06;

    (:typecheck(false))
    function draw(dc, mx, my, mr, awake, frac, eclipse, weak) {
        if (eclipse != null && !eclipse[:lunar]) {
            drawSolar(dc, mx, my, mr, eclipse, weak);
            return;
        }

        var lunarEclipse = (eclipse != null);

        // Unlit disc + outline.
        dc.setColor(Theme.MOON_DARK, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, mr);

        if (lunarEclipse) {
            drawEclipseGlow(dc, mx, my, mr);
        }

        dc.setColor(Theme.MOON_OUTLINE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(mx, my, mr);

        var p = 2.0 * Math.PI * frac;
        var cosP = Math.cos(p);
        var sinP = Math.sin(p);

        // Surface and maria ramps, dark -> lit, built once per draw.
        var litColor; var mareColor;
        if (lunarEclipse) {
            var depth = eclipse[:magnitude];
            if (depth > 1.0) { depth = 1.0; }
            if (depth < 0.2) { depth = 0.2; }
            if (weak) { depth *= 0.7; }
            litColor  = Theme.blend(Theme.MOON_LOW, Theme.ECLIPSE_RED, depth);
            mareColor = Theme.dim(litColor, 0.74);
        } else if (awake) {
            litColor  = Theme.MOON_LIT;
            mareColor = Theme.MOON_MARE;
        } else {
            litColor  = Theme.MOON_LOW;
            mareColor = Theme.MOON_LOW;
        }

        var surface = ramp(lunarEclipse ? Theme.ECLIPSE_RED_EDGE : Theme.MOON_DARK, litColor);
        var maria   = ramp(lunarEclipse ? Theme.ECLIPSE_RED_EDGE : Theme.MOON_DARK, mareColor);

        var step = STEP_PX;
        var last = LEVELS - 1;
        var invMr = 1.0 / mr;

        for (var dy = -mr; dy <= mr; dy += 1) {
            var w2 = mr * mr - dy * dy;
            if (w2 <= 0) { continue; }
            var w = Math.sqrt(w2);
            var y = my + dy;

            // The terminator is a hard edge, so the lit span is computed exactly
            // rather than found by sampling: solving the Lambert term for zero
            // puts it at w * cos(phase), the familiar terminator ellipse. That
            // keeps the day/night edge crisp instead of quantised to the sample
            // grid, while the shading inside the span stays a smooth ramp.
            var xt = w * cosP;
            var lx0; var lx1;
            if (lunarEclipse) {
                lx0 = -w; lx1 = w;              // a lunar eclipse is a full moon
            } else if (sinP >= 0) {
                lx0 = xt; lx1 = w;              // waxing: lit toward the right limb
            } else {
                // Waning: lit toward the left limb, and the terminator runs the
                // other way round. cos(p) is symmetric about frac 0.5, so
                // reusing xt unmirrored would replay the waxing crescents in
                // reverse - a full moon would jump straight to a thin sliver
                // and grow back to full by the next new moon.
                lx0 = -w; lx1 = -xt;
            }
            if (lx1 <= lx0) { continue; }       // this row is entirely dark

            // Pass 1: limb darkening across the lit span, one line per run of
            // equal tone so a smooth ramp costs only a few draw calls.
            var runStart = lx0;
            var runLevel = -1;

            var x = lx0;
            while (x < lx1) {
                var z2 = w2 - x * x;
                var z = (z2 > 0) ? Math.sqrt(z2) * invMr : 0.0;

                // Brightness depends only on how far the surface has turned away
                // from the viewer, which is what makes the disc read as a sphere.
                var shade = LIMB_FLOOR + (1.0 - LIMB_FLOOR) * z + AMBIENT;
                if (shade > 1.0) { shade = 1.0; }
                var level = (shade * last + 0.5).toNumber();

                if (level != runLevel) {
                    if (runLevel > 0 && x > runStart) {
                        dc.setColor(surface[runLevel], Gfx.COLOR_TRANSPARENT);
                        dc.drawLine(mx + runStart, y, mx + x, y);
                    }
                    runStart = x;
                    runLevel = level;
                }
                x += step;
            }
            if (runLevel > 0) {
                dc.setColor(surface[runLevel], Gfx.COLOR_TRANSPARENT);
                dc.drawLine(mx + runStart, y, mx + lx1, y);
            }

            // Pass 2: the maria, one span per crater per row rather than a
            // membership test at every sample. Each span is clipped to the lit
            // span, so a mare crossing the terminator is cut on the same line.
            drawMariaRow(dc, mx, y, dy, w2, mr, invMr, lx0, lx1, maria, last);
        }

        // A thin bright rim on the lit limb, which is what a real terminator
        // photograph shows and what keeps the disc from looking soft-edged. It
        // is faded out with the crescent's width rather than drawn flat: at new
        // moon there is no lit limb to rim, and drawing one anyway was what made
        // a new moon look like a sliver.
        var litWidth = 1.0 - ((cosP < 0) ? -cosP : cosP);
        var rim = litWidth / RIM_FADE;
        if (rim > 1.0) { rim = 1.0; }
        if (awake && !lunarEclipse && rim > 0.05) {
            dc.setColor(Theme.blend(Theme.MOON_DARK, Theme.MOON_LIMB, rim),
                Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            if (frac <= 0.5) {
                dc.drawArc(mx, my, mr - 1, Gfx.ARC_CLOCKWISE, 80, -80);
            } else {
                dc.drawArc(mx, my, mr - 1, Gfx.ARC_COUNTER_CLOCKWISE, 100, 260);
            }
        }
    }

    // Precompute the dark -> bright tones the shading indexes into.
    (:typecheck(false))
    function ramp(dark, bright) {
        var out = new [LEVELS];
        for (var i = 0; i < LEVELS; i += 1) {
            out[i] = Theme.blend(dark, bright, i / ((LEVELS - 1) * 1.0));
        }
        return out;
    }

    // The maria intersected with one scanline. Six spans at most, each shaded
    // by the surface tone at its own midpoint.
    (:typecheck(false))
    function drawMariaRow(dc, mx, y, dy, w2, mr, invMr, lx0, lx1, tones, last) {
        for (var i = 0; i < CRATERS.size(); i += 1) {
            var ccy = CRATERS[i][1] * mr;
            var ccr = CRATERS[i][2] * mr;
            var d = ccr * ccr - (dy - ccy) * (dy - ccy);
            if (d <= 0) { continue; }

            var half = Math.sqrt(d);
            var ccx = CRATERS[i][0] * mr;
            var a = ccx - half;
            var b = ccx + half;
            if (a < lx0) { a = lx0; }
            if (b > lx1) { b = lx1; }
            if (b <= a) { continue; }

            var midX = (a + b) * 0.5;
            var z2 = w2 - midX * midX;
            var z = (z2 > 0) ? Math.sqrt(z2) * invMr : 0.0;

            var shade = LIMB_FLOOR + (1.0 - LIMB_FLOOR) * z + AMBIENT;
            if (shade > 1.0) { shade = 1.0; }

            var level = (shade * last + 0.5).toNumber();
            if (level <= 0) { continue; }
            dc.setColor(tones[level], Gfx.COLOR_TRANSPARENT);
            dc.drawLine(mx + a, y, mx + b, y);
        }
    }

    // Faint red halo outside the disc during a lunar eclipse.
    (:typecheck(false))
    function drawEclipseGlow(dc, mx, my, mr) {
        dc.setPenWidth(1);
        for (var i = 1; i <= 3; i += 1) {
            dc.setColor(Theme.dim(Theme.ECLIPSE_GLOW, 1.0 - (i - 1) * 0.3),
                Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(mx, my, mr + i);
        }
    }

    // Solar eclipse: an occulted disc ringed by corona.
    //
    // Whether it is visible from where you are depends on the path of totality,
    // which the face cannot know, so the corona is drawn faint when the
    // location check could not confirm it.
    (:typecheck(false))
    function drawSolar(dc, mx, my, mr, eclipse, weak) {
        var intensity = weak ? 0.70 : 1.0;

        // Streamers first, so the ring sits on top of them.
        dc.setColor(Theme.dim(Theme.CORONA_DIM, intensity), Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var i = 0; i < 8; i += 1) {
            var a = (i / 8.0) * 2.0 * Math.PI;
            var sa = Math.sin(a);
            var ca = Math.cos(a);
            var len = (i % 2 == 0) ? mr * 1.55 : mr * 1.30;
            dc.drawLine(mx + mr * 1.06 * sa, my - mr * 1.06 * ca,
                        mx + len * sa,       my - len * ca);
        }

        // Corona ring.
        dc.setColor(Theme.dim(Theme.CORONA, intensity), Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(mx, my, mr + 2);
        dc.setPenWidth(1);
        dc.setColor(Theme.dim(Theme.CORONA_DIM, intensity), Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(mx, my, mr + 5);

        // The occulted disc.
        dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, mr);
        dc.setColor(Theme.MOON_OUTLINE, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(mx, my, mr);
    }
}
