using Toybox.Time;
using Toybox.Math;

// Lunar phase from the mean synodic month. Accurate to a few hours, which is
// far finer than a watch face can display. No UI dependencies here.
module MoonPhase {
    const SYNODIC        = 29.530588853;   // mean synodic month, days
    const REF_NEW_MOON   = 2451550.1;      // JD of new moon 2000-01-06 18:14 UTC
    const UNIX_EPOCH_JD  = 2440587.5;      // JD at unix epoch

    // Phase fraction 0..1 for a unix epoch time in seconds.
    // 0.0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    function fractionAt(epochSeconds) {
        var jd  = epochSeconds / 86400.0 + UNIX_EPOCH_JD;
        var age = fmod(jd - REF_NEW_MOON, SYNODIC);
        if (age < 0.0) { age += SYNODIC; }
        return age / SYNODIC;
    }

    function fraction() {
        return fractionAt(Time.now().value());
    }

    // Illuminated fraction of the disc, 0..1.
    function illumination(frac) {
        return (1.0 - Math.cos(2.0 * Math.PI * frac)) / 2.0;
    }

    // Nearest of the 8 named phases, 0..7.
    function phaseIndex(frac) {
        var idx = Math.floor(frac * 8.0 + 0.5).toNumber();
        return idx % 8;
    }

    function phaseName(frac) {
        var names = [
            "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
            "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"
        ];
        return names[phaseIndex(frac)];
    }

    // Floating-point modulo (Math has no fmod in this API).
    function fmod(a, b) {
        return a - b * Math.floor(a / b);
    }
}
