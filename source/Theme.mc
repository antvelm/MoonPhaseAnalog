using Toybox.Math;

// Central palette and colour helpers.
//
// Design rule: everything static is monochrome; the only colour on the dial
// is the moving second hand and its comet tail (full-spectrum hue sweep),
// plus the warm moon. Swap the constants here to re-theme the whole face.
module Theme {
    // --- Monochrome base (packed 0xRRGGBB) ---
    const BG           = 0x000000;   // true black (AMOLED pixels off)
    const WHITE        = 0xFFFFFF;
    const HAND_FILL    = 0xE6E6EC;   // cool white spine
    const HAND_OUTLINE = 0xFFFFFF;
    const HAND_DIM     = 0x5A5A62;   // low-power outline
    const TICK_DIM     = 0x363640;   // minute dots
    const TICK_MAJOR   = 0x9AA0AA;   // quarter dots
    const NUMERAL      = 0x8A8A92;
    const ORBIT_RING   = 0x1C1C22;
    const STAR         = 0x50505A;
    const READOUT      = 0xCACAD2;
    const READOUT_DIM  = 0x66666E;
    const HR_HEART     = 0xC85A5A;   // muted red heart glyph
    const HUB          = 0xFFFFFF;

    // --- Moon palette (flat tones; 16bpp panel bands soft gradients) ---
    const MOON_LIT     = 0xEBE8DC;   // warm off-white lit surface
    const MOON_MARE    = 0xC6C4BA;   // slightly darker maria
    const MOON_DARK    = 0x141416;   // near-black unlit disc
    const MOON_OUTLINE = 0x2C2C30;
    const MOON_LIMB    = 0xFFFDF2;   // bright limb highlight
    const MOON_LOW     = 0x8A887E;   // dimmed lit surface in low power

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
}
