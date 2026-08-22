using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Lang;

// Hour and minute hand silhouette: a tapered baton, capped at both ends by a
// circle and sided by the two external tangents of those circles.
//
// The whole outline — caps included — is emitted as one closed polygon, so a
// single rasteriser draws it. Filling the shaft and then stamping a separate
// circle on the end left the cap a pixel off the shaft edges, because the two
// primitives round their coverage independently; a single polygon cannot come
// apart that way. The tangent construction is also what keeps the cap flush on
// a tapered hand: on a taper the sides meet the cap slightly past its widest
// point, not at it.
//
// Built in a local frame whose tip points toward -y, then rotated by the hand
// angle.
module Hands {

    // Segments per cap. The tail cap ends up mostly under the hub, so it gets
    // away with fewer.
    const TIP_SEGMENTS  = 10;
    const TAIL_SEGMENTS = 6;

    // Floors for the hollow style, in device pixels. A border thinner than
    // MIN_RIM disappears into the background, and a core narrower than
    // MIN_CORE is a ragged slit rather than a cut-out; either way the hand is
    // better off solid.
    const MIN_RIM  = 1.0;
    const MIN_CORE = 1.0;

    // How far the chosen hand colour is pulled down in always-on mode. 0.35
    // lands plain white on 0x595959, which is where the old fixed low-power
    // grey sat - so white hands look exactly as they did, and a coloured hand
    // now keeps its hue when dimmed instead of reverting to grey.
    const LOW_POWER_LEVEL = 0.35;

    // Set once per frame by the view; saves threading them through every call.
    var _cx = 0;
    var _cy = 0;
    var _scale = 1.0;
    var _color = Theme.HAND_WHITE;

    function setup(cx, cy, scale, sec) {
        _cx = cx;
        _cy = cy;
        _scale = scale;
        _color = baseColor(sec);
    }

    // The hand colour before the rainbow wave gets a say. Spectrum rides the
    // same hue as the second hand, so the whole time display glows as one and
    // turns through the wheel over a minute; the rest are fixed presets.
    (:typecheck(false))
    function baseColor(sec) {
        if (Settings.handColor == Settings.HAND_COLOR_SPECTRUM) {
            return Theme.hsvToColor(Theme.hueForSecond(sec), 0.55, 1.0);
        }
        return Theme.handPreset(Settings.handColor);
    }

    function scaled(v) {
        return (v * _scale + 0.5).toNumber();
    }

    // Draw one hand.
    //   angle      radians, 0 = straight up, increasing clockwise
    //   length     tip distance from centre, pixels
    //   baseHalf   half width at the widest point, just behind the hub
    //   tipHalf    half width at the tip, i.e. the tip cap's radius
    //   tail       counterweight length past the centre, pixels
    //   awake      false => low-power wireframe
    (:typecheck(false))
    function draw(dc, angle, length, baseHalf, tipHalf, tail, awake) {
        var ca = Math.cos(angle);
        var sa = Math.sin(angle);
        var body = outline(length, baseHalf, tipHalf, tail, ca, sa);

        // Hollow interior. The silhouette is the convex hull of the two cap
        // circles, and shrinking both radii by a constant while their centres
        // stay put is exactly a uniform inward offset of that hull - so the
        // same builder, run with every dimension pulled in by `rim`, gives a
        // border of even thickness with no second construction to keep in step.
        // Passing length and tail in reduced by the same amount is what holds
        // the two centres still.
        var rim = rimWidth(tipHalf);
        var core = null;
        if (rim != null) {
            core = outline(length - rim, baseHalf - rim, tipHalf - rim, tail - rim, ca, sa);
        }

        if (!awake) {
            dc.setColor(Theme.dim(_color, LOW_POWER_LEVEL), Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            strokePolygon(dc, body);
            if (core != null) { strokePolygon(dc, core); }
            return;
        }

        // Tint at the hand's midpoint so the rainbow wave washes over it.
        var midX = _cx + length * 0.5 * sa;
        var midY = _cy - length * 0.5 * ca;
        var color = RainbowWave.tint(_color, midX, midY);

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(body);

        if (core != null) {
            // Dc has no clipping, so the cut-out is repainted in the dial's own
            // black rather than left see-through. On an AMOLED face that reads
            // the same everywhere except over the moon subdial, which the hand
            // would have covered solid anyway.
            dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
            dc.fillPolygon(core);
        }
    }

    // Border thickness for the hollow style, or null to draw the hand solid.
    // Settings.handHollow is the cut-out's width as a percentage of the hand's
    // width at the tip; the border it implies there is then held constant all
    // the way down, so the cut-out opens up towards the centre along with the
    // hand.
    (:typecheck(false))
    function rimWidth(tipHalf) {
        var pct = Settings.handHollow;
        if (pct <= 0) { return null; }

        var rim = tipHalf * (1.0 - pct / 100.0);
        if (rim < MIN_RIM) { rim = MIN_RIM; }
        if (tipHalf - rim < MIN_CORE) { return null; }
        return rim;
    }

    // The closed silhouette in screen space: tip cap first, then round the
    // back over the tail cap. Points on a cap are centre + r * (sin t, -cos t),
    // so t = 0 points at the tip.
    (:typecheck(false))
    function outline(length, baseHalf, tipHalf, tail, ca, sa) {
        var tipY  = -(length - tipHalf);   // tip cap centre
        var tailY = tail - baseHalf;       // tail cap centre
        var span  = tailY - tipY;

        // A tangent touching both caps leaves each one leaning off the waist by
        // asin((baseHalf - tipHalf) / span). With no taper that is zero and the
        // caps are plain semicircles.
        var lean = 0.0;
        if (span > 0.0) {
            var s = (baseHalf - tipHalf) / span;
            if (s > 1.0) { s = 1.0; } else if (s < -1.0) { s = -1.0; }
            lean = Math.asin(s);
        }
        var edge = Math.PI / 2.0 - lean;   // half-sweep of the tip cap

        var pts = new [TIP_SEGMENTS + TAIL_SEGMENTS + 2];
        var n = 0;

        // Tip cap: -x tangent point, over the tip, to the +x tangent point.
        var step = 2.0 * edge / TIP_SEGMENTS;
        for (var i = 0; i <= TIP_SEGMENTS; i += 1) {
            var t = -edge + step * i;
            pts[n] = rot(tipHalf * Math.sin(t), tipY - tipHalf * Math.cos(t), ca, sa);
            n += 1;
        }

        // Tail cap: on round the back, landing where the tip cap started.
        step = (2.0 * Math.PI - 2.0 * edge) / TAIL_SEGMENTS;
        for (var i = 0; i <= TAIL_SEGMENTS; i += 1) {
            var t = edge + step * i;
            pts[n] = rot(baseHalf * Math.sin(t), tailY - baseHalf * Math.cos(t), ca, sa);
            n += 1;
        }

        return pts;
    }

    // Rotate a local point (tip toward -y) into screen space.
    function rot(lx, ly, ca, sa) {
        return [
            _cx + lx * ca - ly * sa,
            _cy + lx * sa + ly * ca
        ];
    }

    // Dc has fillPolygon but no drawPolygon, so outline mode walks the edges.
    (:typecheck(false))
    function strokePolygon(dc, pts) {
        var n = pts.size();
        for (var i = 0; i < n; i += 1) {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }
}
