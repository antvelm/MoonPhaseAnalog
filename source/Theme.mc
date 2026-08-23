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
    const HAND_OUTLINE = 0xFFFFFF;
    const TICK_DIM     = 0x363640;   // minute dots
    const TICK_MAJOR   = 0x9AA0AA;   // quarter dots
    const ORBIT_RING   = 0x1C1C22;
    const READOUT      = 0xCACAD2;
    const READOUT_DIM  = 0x66666E;
    const HR_HEART     = 0xC85A5A;   // muted red heart glyph
    const HUB          = 0xFFFFFF;

    // --- Hand colour presets (Settings.HandColor) ---
    // Every one of these is a light tint rather than a saturated hue: the hands
    // sit over a black dial and have to stay legible at a glance, which a deep
    // colour at this stroke width does not manage. The low-power tone is not
    // listed - it is the chosen colour scaled by Hands.LOW_POWER_LEVEL, so a
    // dim hand keeps its hue instead of reverting to grey.
    const HAND_WHITE   = 0xFFFFFF;
    const HAND_COOL    = 0xE6E6EC;   // cool white, a shade off pure
    const HAND_LUME    = 0xD8F4E4;   // green-white, old radium lume
    const HAND_ICE     = 0x8CCCF0;
    const HAND_AMBER   = 0xF0B43C;
    const HAND_ORANGE  = 0xF07028;
    const HAND_RED     = 0xE2483C;
    const HAND_MAGENTA = 0xE05CC8;

    // Settings.HandColor index -> packed colour. The spectrum entry is not
    // here: it has no fixed value and is resolved per frame in Hands.baseColor.
    function handPreset(choice) {
        if (choice == 1) { return HAND_COOL; }
        if (choice == 2) { return HAND_LUME; }
        if (choice == 3) { return HAND_ICE; }
        if (choice == 4) { return HAND_AMBER; }
        if (choice == 5) { return HAND_ORANGE; }
        if (choice == 6) { return HAND_RED; }
        if (choice == 7) { return HAND_MAGENTA; }
        return HAND_WHITE;
    }

    // --- Numeral rings ---
    // Hours read bright so they carry the time; seconds stay grey so the
    // outer ring never competes with them.
    const NUMERAL      = 0xFFFFFF;   // hour numerals, bright white
    const NUMERAL_DIM  = 0x6E6E78;   // hour numerals in low power
    const SEC_NUMERAL  = 0x70707A;   // 5-second numerals, grey
    const SEC_NUM_Q    = 0x9EA4AE;   // quarter seconds (60/15/30/45), a step up
    const DAY_WEEK     = 0x8A8A92;   // the "FRI" half of the date

    // --- Hour tick lines (Settings.hourMarkStyle's two Lines modes) ---
    // Major ticks stand in for a numeral, so they stay a step above the minors;
    // they are not full white, so they do not compete with the hands. The _DIM
    // pair is low power. Widths are pen widths in pixels before Dial.scaled();
    // the matching tick lengths are geometry and stay in Dial.
    const HOUR_TICK_MAJOR     = 0xB0B4BC;
    const HOUR_TICK_MAJOR_DIM = 0x4A4A52;
    const HOUR_TICK_MINOR     = 0x6E7480;
    const HOUR_TICK_MINOR_DIM = 0x2A2A32;
    const HOUR_TICK_MAJOR_W   = 5;
    const HOUR_TICK_MINOR_W   = 6;

    // --- Background ornament ---
    // The three star tiers. These are the colour before Dial's moonlight fade
    // multiplies them down, so the faint end has to start high: STAR_DIM stars
    // are a single pixel, and Dial.starLevel puts most of them out at roughly
    // two thirds of this value. At the old 0x4E4E58 that landed near RGB 50 on
    // an AMOLED black, below the point the eye picks a lone pixel out at all,
    // so a 200-star field read as the forty-odd cross and sparkle sprites and
    // nothing else. The ladder still rises with the tier, so a brighter star
    // is still a brighter pixel as well as a bigger sprite.
    const STAR         = 0xAAAABC;   // mid star: the small cross
    const STAR_DIM     = 0x8C8C9C;   // faint field stars; see Dial.STAR_LEVEL_MIN
    const STAR_BRIGHT  = 0xDCE2EE;
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
