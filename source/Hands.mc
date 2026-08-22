using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Lang;

// Hour and minute hand silhouettes.
//
// Seven styles, selected by the HandStyle property, so the final look can be
// picked by eye on the watch instead of being decided in code. Every style is
// built from polygons in a local frame whose tip points toward -y, then rotated
// by the hand angle -- so adding an eighth style means adding one case to
// silhouette() and, if it needs one, one case to decorate().
module Hands {

    const DAUPHINE = 0;
    const BATON    = 1;
    const SYRINGE  = 2;
    const SKELETON = 3;
    const BREGUET  = 4;
    const ALPHA    = 5;
    const SWORD    = 6;

    const STYLE_COUNT = 7;

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
    //   halfWidth  nominal half width at the widest point, pixels
    //   tail       counterweight length past the centre, pixels
    //   awake      false => low-power wireframe
    (:typecheck(false))
    function draw(dc, style, angle, length, halfWidth, tail, awake) {
        var ca = Math.cos(angle);
        var sa = Math.sin(angle);

        var outer = silhouette(style, ca, sa, length, halfWidth, tail);

        if (!awake) {
            dc.setColor(Theme.HAND_DIM, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            strokePolygon(dc, outer);
            return;
        }

        // Tint at the hand's midpoint so the rainbow wave washes over it.
        var midX = _cx - length * 0.5 * sa;
        var midY = _cy - length * 0.5 * ca;
        var body = RainbowWave.tint(Theme.HAND_OUTLINE, midX, midY);

        dc.setColor(body, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(outer);

        decorate(dc, style, ca, sa, length, halfWidth, tail, body);
    }

    // The outer shape of each style, in the rotated screen frame.
    (:typecheck(false))
    function silhouette(style, ca, sa, len, hw, tail) {
        switch (style) {
            case BATON:
                return [
                    rot( hw, -len, ca, sa),
                    rot( hw,  tail, ca, sa),
                    rot(-hw,  tail, ca, sa),
                    rot(-hw, -len, ca, sa)
                ];

            case SYRINGE:
                var neck = -len * 0.62;
                var shaft = hw * 0.42;
                return [
                    rot(0, -len, ca, sa),
                    rot( hw * 0.85, neck, ca, sa),
                    rot( shaft, neck, ca, sa),
                    rot( shaft, tail, ca, sa),
                    rot(-shaft, tail, ca, sa),
                    rot(-shaft, neck, ca, sa),
                    rot(-hw * 0.85, neck, ca, sa)
                ];

            case SKELETON:
                return [
                    rot(0, -len, ca, sa),
                    rot( hw, -len * 0.5, ca, sa),
                    rot( hw * 0.6, tail, ca, sa),
                    rot(-hw * 0.6, tail, ca, sa),
                    rot(-hw, -len * 0.5, ca, sa)
                ];

            case BREGUET:
                // Slim shaft; the pierced circle near the tip is drawn in
                // decorate() so the hole can be punched out of it.
                var stem = hw * 0.30;
                return [
                    rot( stem, -len, ca, sa),
                    rot( stem,  tail, ca, sa),
                    rot(-stem,  tail, ca, sa),
                    rot(-stem, -len, ca, sa)
                ];

            case ALPHA:
                var shoulder = -len * 0.32;
                var waist = hw * 0.5;
                return [
                    rot(0, -len, ca, sa),
                    rot( hw * 1.35, shoulder, ca, sa),
                    rot( waist, shoulder, ca, sa),
                    rot( waist, tail, ca, sa),
                    rot(-waist, tail, ca, sa),
                    rot(-waist, shoulder, ca, sa),
                    rot(-hw * 1.35, shoulder, ca, sa)
                ];

            case SWORD:
                return [
                    rot(0, -len, ca, sa),
                    rot( hw * 0.72, -len * 0.76, ca, sa),
                    rot( hw * 0.52, tail * 0.2, ca, sa),
                    rot( hw * 0.46, tail, ca, sa),
                    rot(-hw * 0.46, tail, ca, sa),
                    rot(-hw * 0.52, tail * 0.2, ca, sa),
                    rot(-hw * 0.72, -len * 0.76, ca, sa)
                ];

            default:   // DAUPHINE
                return [
                    rot(0, -len, ca, sa),
                    rot( hw, -len * 0.42, ca, sa),
                    rot( hw * 0.45, tail, ca, sa),
                    rot(-hw * 0.45, tail, ca, sa),
                    rot(-hw, -len * 0.42, ca, sa)
                ];
        }
    }

    // Per-style detailing drawn on top of the filled silhouette.
    (:typecheck(false))
    function decorate(dc, style, ca, sa, len, hw, tail, body) {
        switch (style) {
            case DAUPHINE:
                // The facet: shade the left half so the blade reads as folded
                // along its centreline rather than flat.
                dc.setColor(Theme.dim(body, 0.62), Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon([
                    rot(0, -len, ca, sa),
                    rot(0, tail, ca, sa),
                    rot(-hw * 0.45, tail, ca, sa),
                    rot(-hw, -len * 0.42, ca, sa)
                ]);
                break;

            case BATON:
                // Lume block near the tip.
                var lw = hw * 0.55;
                dc.setColor(Theme.HAND_LUME, Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon([
                    rot( lw, -len * 0.94, ca, sa),
                    rot( lw, -len * 0.60, ca, sa),
                    rot(-lw, -len * 0.60, ca, sa),
                    rot(-lw, -len * 0.94, ca, sa)
                ]);
                break;

            case SKELETON:
                // Hollow it out, then lay a thin spine back down the middle.
                var inner = silhouette(SKELETON, ca, sa, len - scaled(4), hw * 0.52, tail * 0.5);
                dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon(inner);
                var spine = silhouette(SKELETON, ca, sa, len - scaled(3), hw * 0.16, tail * 0.4);
                dc.setColor(Theme.dim(body, 0.85), Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon(spine);
                break;

            case BREGUET:
                // Pomme: a filled circle near the tip with the centre punched out.
                var pr = hw * 0.95;
                var pc = rot(0, -len * 0.80, ca, sa);
                dc.setColor(body, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(pc[0], pc[1], pr);
                dc.setColor(Theme.BG, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(pc[0], pc[1], pr * 0.52);
                break;

            case SWORD:
                // Bevel down one edge.
                dc.setColor(Theme.dim(body, 0.55), Gfx.COLOR_TRANSPARENT);
                dc.fillPolygon([
                    rot(0, -len, ca, sa),
                    rot(0, tail, ca, sa),
                    rot(-hw * 0.46, tail, ca, sa),
                    rot(-hw * 0.52, tail * 0.2, ca, sa),
                    rot(-hw * 0.72, -len * 0.76, ca, sa)
                ]);
                break;
        }
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
