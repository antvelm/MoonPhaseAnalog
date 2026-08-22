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

    // Set once per frame by the view; saves threading them through every call.
    var _cx = 0;
    var _cy = 0;
    var _scale = 1.0;

    function setup(cx, cy, scale) {
        _cx = cx;
        _cy = cy;
        _scale = scale;
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

        if (!awake) {
            dc.setColor(Theme.HAND_DIM, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            strokePolygon(dc, body);
            return;
        }

        // Tint at the hand's midpoint so the rainbow wave washes over it.
        var midX = _cx + length * 0.5 * sa;
        var midY = _cy - length * 0.5 * ca;
        var color = RainbowWave.tint(Theme.HAND_OUTLINE, midX, midY);

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(body);
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
