using Toybox.Math;

// Central palette and colour helpers.
//
// Design rule: everything static is monochrome; the only colour on the dial
// is the moving second hand and its comet tail (full-spectrum hue sweep),
// the once-a-day rainbow wave, and the warm moon. Swap the constants here to
// re-theme the whole face.
module Theme {
    // --- Monochrome base (packed 0xRRGGBB) ---
    const BG           = 0x000000;   // true black (AMOLED pixels off)
    const WHITE        = 0xFFFFFF;
    const HAND_FILL    = 0xE6E6EC;   // cool white spine
    const HAND_OUTLINE = 0xFFFFFF;
    const HAND_DIM     = 0x5A5A62;   // low-power outline
    const HAND_LUME    = 0xD8F4E4;   // faint green-white lume block (baton style)
    const TICK_DIM     = 0x363640;   // minute dots
    const TICK_MAJOR   = 0x9AA0AA;   // quarter dots
    const ORBIT_RING   = 0x1C1C22;
    const READOUT      = 0xCACAD2;
    const READOUT_DIM  = 0x66666E;
    const HR_HEART     = 0xC85A5A;   // muted red heart glyph
    const HUB          = 0xFFFFFF;

    // --- Numeral rings ---
    // Hours read bright so they carry the time; seconds stay grey so the
    // outer ring never competes with them.
    const NUMERAL      = 0xFFFFFF;   // hour numerals, bright white
    const NUMERAL_DIM  = 0x6E6E78;   // hour numerals in low power
    const SEC_NUMERAL  = 0x70707A;   // 5-second numerals, grey
    const SEC_NUM_Q    = 0x9EA4AE;   // quarter seconds (60/15/30/45), a step up
    const DAY_WEEK     = 0x8A8A92;   // the "FRI" half of the date

    // --- Background ornament ---
    const STAR         = 0x50505A;   // legacy / mid star
    const STAR_DIM     = 0x3A3A44;
    const STAR_BRIGHT  = 0x9096A2;
    const ZODIAC_LINE  = 0x24242C;   // constellation sticks: present, never loud

    // --- Moon palette (flat tones; 16bpp panel bands soft gradients) ---
    const MOON_LIT        = 0xEBE8DC;   // warm off-white lit surface
    const MOON_MARE       = 0xC6C4BA;   // slightly darker maria
    const MOON_DARK       = 0x141416;   // near-black unlit disc
    const MOON_OUTLINE    = 0x2C2C30;
    const MOON_LIMB       = 0xFFFDF2;   // bright limb highlight
    const MOON_LOW        = 0x8A887E;   // dimmed lit surface in low power
    const MOON_LIMB_DARK  = 0xBFBDB2;   // limb darkening, first step
    const MOON_LIMB_DARK2 = 0x8E8C84;   // limb darkening, outermost step
    const MOON_TERM_SOFT  = 0x9A988E;   // softened terminator band

    // --- Eclipse ---
    const ECLIPSE_RED      = 0xB4442A;  // copper, centre of a blood moon
    const ECLIPSE_RED_DEEP = 0x6B2216;  // deeper red toward the limb
    const ECLIPSE_RED_EDGE = 0x3A120C;  // outermost rim
    const ECLIPSE_GLOW     = 0x2A0C08;  // faint halo outside the disc
    const CORONA           = 0xF2F0E4;  // solar corona ring
    const CORONA_DIM       = 0x5C5C56;  // corona streamers

    // HSV -> packed RGB. h in degrees [0,360), s and v in [0,1].
    function hsvToColor(h, s, v) {
        var hh = h / 60.0;
        var i = Math.floor(hh).toNumber();
        if (i >= 6) { i = 5; }
        if (i < 0)  { i = 0; }
        var f = hh - i;
        var p = v * (1.0 - s);
        var q = v * (1.0 - s * f);
        var t = v * (1.0 - s * (1.0 - f));
        var r; var g; var b;
        if (i == 0)      { r = v; g = t; b = p; }
        else if (i == 1) { r = q; g = v; b = p; }
        else if (i == 2) { r = p; g = v; b = t; }
        else if (i == 3) { r = p; g = q; b = v; }
        else if (i == 4) { r = t; g = p; b = v; }
        else             { r = v; g = p; b = q; }
        var ri = ((r * 255.0) + 0.5).toNumber();
        var gi = ((g * 255.0) + 0.5).toNumber();
        var bi = ((b * 255.0) + 0.5).toNumber();
        return (ri << 16) | (gi << 8) | bi;
    }

    // Hue for a given second (0..59): one full turn of the wheel per minute.
    function hueForSecond(sec) {
        return (sec / 60.0) * 360.0;
    }

    // Linear blend of two packed colours. t = 0 -> a, t = 1 -> b.
    function blend(a, b, t) {
        if (t <= 0.0) { return a; }
        if (t >= 1.0) { return b; }
        var ar = (a >> 16) & 0xFF;
        var ag = (a >> 8) & 0xFF;
        var ab = a & 0xFF;
        var br = (b >> 16) & 0xFF;
        var bg = (b >> 8) & 0xFF;
        var bb = b & 0xFF;
        var r = (ar + (br - ar) * t + 0.5).toNumber();
        var g = (ag + (bg - ag) * t + 0.5).toNumber();
        var bl = (ab + (bb - ab) * t + 0.5).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // Scale a packed colour's brightness by f (clamped to 0..1 per channel).
    function dim(c, f) {
        if (f >= 1.0) { return c; }
        if (f <= 0.0) { return BG; }
        var r = (((c >> 16) & 0xFF) * f + 0.5).toNumber();
        var g = (((c >> 8) & 0xFF) * f + 0.5).toNumber();
        var b = ((c & 0xFF) * f + 0.5).toNumber();
        if (r > 255) { r = 255; }
        if (g > 255) { g = 255; }
        if (b > 255) { b = 255; }
        return (r << 16) | (g << 8) | b;
    }
}
