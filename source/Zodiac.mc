using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Lang;

// Zodiac constellations as star patterns.
//
// Astronomy only: the principal stars of each constellation and, optionally,
// the conventional lines between them. No sign glyphs, no figures, no artwork.
//
// Each pattern is a flat array of [x, y, magnitude] triples in rough -1..1
// coordinates (y down, screen convention), and a flat array of index pairs for
// the connecting lines. Flat arrays rather than nested ones: 12 constellations
// of nested pairs would be several hundred small objects held for the life of
// the face. The renderer fits whatever bounds the chosen pattern has, so these
// coordinates only need to be right relative to each other.
module Zodiac {

    const ARIES = 1;
    const PISCES = 12;

    // Brightness tiers the renderer draws with, from the star's magnitude.
    function tierFor(mag) {
        if (mag < 2.2) { return 2; }
        if (mag < 3.4) { return 1; }
        return 0;
    }

    // --- Star patterns: x, y, visual magnitude ------------------------------

    const S_ARI = [
        -0.10, -0.25, 2.0,   // Hamal
        -0.55,  0.05, 2.6,   // Sheratan
        -0.72,  0.16, 3.9,   // Mesarthim
         0.35,  0.30, 3.6,   // 41 Arietis
         0.62,  0.44, 4.4    // 39 Arietis
    ];
    const L_ARI = [4, 3, 3, 0, 0, 1, 1, 2];

    const S_TAU = [
         0.05,  0.20, 0.9,   // Aldebaran
         0.12,  0.02, 3.5,   // Epsilon
         0.55, -0.62, 1.7,   // Elnath
         0.75,  0.10, 3.0,   // Zeta
        -0.14,  0.28, 3.8,   // Delta
        -0.28,  0.40, 3.6,   // Gamma
        -0.52,  0.52, 3.4,   // Lambda
        -0.78,  0.60, 3.7    // Xi
    ];
    const L_TAU = [2, 1, 1, 0, 0, 3, 0, 4, 4, 5, 5, 6, 6, 7];

    const S_GEM = [
         0.10, -0.78, 1.6,   // Castor
         0.40, -0.62, 1.1,   // Pollux
        -0.02, -0.42, 4.4,   // Tau
         0.34, -0.32, 4.0,   // Upsilon
        -0.22, -0.10, 3.0,   // Mebsuta
         0.28,  0.02, 3.5,   // Wasat
         0.22,  0.34, 3.8,   // Mekbuda
         0.05,  0.55, 1.9,   // Alhena
        -0.42,  0.10, 2.9,   // Tejat
        -0.55,  0.22, 3.3,   // Propus
         0.52,  0.56, 3.3    // Xi
    ];
    const L_GEM = [0, 2, 2, 4, 4, 8, 8, 9, 1, 3, 3, 5, 5, 6, 6, 7, 5, 10];

    const S_CNC = [
         0.35,  0.40, 4.3,   // Acubens
         0.05,  0.05, 3.9,   // Asellus Australis
         0.02, -0.20, 4.7,   // Asellus Borealis
        -0.34,  0.62, 3.5,   // Altarf
         0.12, -0.62, 4.0    // Iota
    ];
    const L_CNC = [0, 1, 1, 2, 2, 4, 1, 3];

    const S_LEO = [
        -0.35,  0.30, 1.4,   // Regulus
        -0.38,  0.10, 3.5,   // Eta
        -0.30, -0.08, 2.0,   // Algieba
        -0.34, -0.26, 3.4,   // Adhafera
        -0.48, -0.40, 3.9,   // Rasalas
        -0.68, -0.32, 3.0,   // Ras Elased
         0.28, -0.22, 2.5,   // Zosma
         0.32,  0.14, 3.3,   // Chertan
         0.74, -0.16, 2.1    // Denebola
    ];
    const L_LEO = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 0, 7, 7, 6, 6, 8, 8, 7, 2, 6];

    const S_VIR = [
         0.30,  0.62, 1.0,   // Spica
        -0.05,  0.10, 2.7,   // Porrima
        -0.14, -0.14, 3.4,   // Delta
         0.05, -0.40, 2.8,   // Vindemiatrix
         0.44,  0.18, 3.4,   // Zeta
        -0.44,  0.14, 3.9,   // Zaniah
        -0.78,  0.02, 3.6,   // Zavijava
         0.74,  0.30, 4.1    // Iota
    ];
    const L_VIR = [6, 5, 5, 1, 1, 2, 2, 3, 1, 0, 0, 4, 4, 7];

    const S_LIB = [
         0.10, -0.44, 2.6,   // Zubeneschamali
        -0.34,  0.18, 2.7,   // Zubenelgenubi
         0.44,  0.36, 3.3,   // Sigma
         0.50, -0.10, 3.9    // Gamma
    ];
    const L_LIB = [1, 0, 0, 3, 3, 2, 2, 1];

    const S_SCO = [
         0.00,  0.05, 1.1,   // Antares
        -0.08, -0.14, 2.9,   // Sigma
        -0.22, -0.36, 2.3,   // Dschubba
        -0.10, -0.52, 2.6,   // Acrab
        -0.40, -0.28, 2.9,   // Pi
         0.10,  0.22, 2.8,   // Tau
         0.18,  0.42, 2.3,   // Epsilon
         0.22,  0.58, 3.0,   // Mu
         0.15,  0.72, 3.6,   // Zeta
         0.02,  0.82, 3.3,   // Eta
        -0.20,  0.88, 1.9,   // Sargas
        -0.44,  0.82, 3.0,   // Iota
        -0.60,  0.70, 2.4,   // Kappa
        -0.68,  0.55, 1.6,   // Shaula
        -0.76,  0.63, 2.7    // Lesath
    ];
    const L_SCO = [
        4, 2, 2, 1, 1, 0, 3, 2, 0, 5, 5, 6, 6, 7, 7, 8,
        8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14
    ];

    const S_SGR = [
        -0.58,  0.30, 3.0,   // Gamma
        -0.30,  0.10, 2.7,   // Kaus Media
        -0.34,  0.50, 1.8,   // Kaus Australis
        -0.05, -0.16, 2.8,   // Kaus Borealis
         0.16,  0.02, 3.2,   // Phi
         0.30, -0.16, 2.0,   // Nunki
         0.48,  0.10, 3.3,   // Tau
         0.32,  0.36, 2.6,   // Ascella
        -0.18,  0.70, 3.1    // Eta
    ];
    const L_SGR = [0, 1, 1, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 4, 1, 2, 2, 7, 2, 8];

    const S_CAP = [
        -0.64, -0.30, 3.6,   // Algedi
        -0.56, -0.12, 3.1,   // Dabih
         0.70,  0.10, 2.8,   // Deneb Algedi
         0.54,  0.06, 3.7,   // Nashira
        -0.22,  0.44, 4.1,   // Omega
         0.20,  0.50, 3.7,   // Zeta
         0.02,  0.10, 4.1    // Theta
    ];
    const L_CAP = [0, 1, 1, 6, 6, 4, 4, 5, 5, 3, 3, 2, 2, 5];

    const S_AQR = [
        -0.20, -0.32, 2.9,   // Sadalmelik
        -0.64, -0.12, 2.9,   // Sadalsuud
         0.02, -0.36, 3.8,   // Sadachbia
         0.12, -0.22, 3.6,   // Zeta
         0.24, -0.32, 4.0,   // Eta
         0.36,  0.44, 3.3,   // Skat
         0.30,  0.18, 4.0,   // Tau
         0.50,  0.06, 3.7,   // Lambda
        -0.84,  0.30, 3.8    // Albali
    ];
    const L_AQR = [1, 0, 0, 3, 3, 2, 3, 4, 3, 7, 7, 6, 6, 5, 1, 8];

    const S_PSC = [
         0.64,  0.36, 3.8,   // Alrescha
         0.44,  0.10, 4.4,   // Nu
         0.18, -0.06, 4.3,   // Epsilon
         0.05, -0.20, 4.4,   // Delta
        -0.16, -0.32, 4.0,   // Omega
        -0.44, -0.44, 4.1,   // Iota
        -0.58, -0.32, 4.3,   // Theta
        -0.72, -0.18, 3.7,   // Gamma
        -0.64, -0.04, 4.9,   // Kappa
        -0.48, -0.10, 4.5,   // Lambda
         0.50, -0.36, 3.6,   // Eta
         0.58,  0.06, 4.3    // Omicron
    ];
    const L_PSC = [
        0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 5,
        0, 11, 11, 10
    ];

    // --- Access -------------------------------------------------------------

    (:typecheck(false))
    function stars(sign) {
        switch (sign) {
            case 1:  return S_ARI;
            case 2:  return S_TAU;
            case 3:  return S_GEM;
            case 4:  return S_CNC;
            case 5:  return S_LEO;
            case 6:  return S_VIR;
            case 7:  return S_LIB;
            case 8:  return S_SCO;
            case 9:  return S_SGR;
            case 10: return S_CAP;
            case 11: return S_AQR;
            default: return S_PSC;
        }
    }

    (:typecheck(false))
    function lines(sign) {
        switch (sign) {
            case 1:  return L_ARI;
            case 2:  return L_TAU;
            case 3:  return L_GEM;
            case 4:  return L_CNC;
            case 5:  return L_LEO;
            case 6:  return L_VIR;
            case 7:  return L_LIB;
            case 8:  return L_SCO;
            case 9:  return L_SGR;
            case 10: return L_CAP;
            case 11: return L_AQR;
            default: return L_PSC;
        }
    }

    // Tropical sun sign for the current date, 1 = Aries .. 12 = Pisces.
    // Used when ZodiacSign is left on auto, so the background follows the season.
    (:typecheck(false))
    function currentSign() {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return signFor(info.month, info.day);
    }

    function signFor(month, day) {
        // Each entry is the day the sign starting in that month begins.
        var starts = [20, 19, 21, 20, 21, 21, 23, 23, 23, 23, 22, 22];
        // month 1 (Jan) begins Capricorn until the 19th, then Aquarius.
        var idx = month - 1;
        if (day >= starts[idx]) {
            // The sign that starts this month.
            var s = month + 9;          // Jan -> 10 (Capricorn) + 1 = Aquarius
            s = s % 12;
            return s + 1;
        }
        var p = month + 8;
        p = p % 12;
        return p + 1;
    }
}
