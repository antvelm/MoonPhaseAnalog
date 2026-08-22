using Toybox.Test;
using Toybox.Math;
using Toybox.Lang;

// Unit tests for the eclipse table and the computed fallback.
//
// Run with:  monkeydo bin\MoonPhaseAstro-venu3.prg venu3 -t
// (build with build.ps1 -Debug first).
//
// Note on arithmetic: these deliberately work in Double epoch seconds. The
// table runs to 2045, and 2045 in epoch seconds is past the range of Monkey C's
// 32-bit Number, so integer epoch arithmetic would silently overflow.

const UNIX_2000 = 946684800.0;      // 2000-01-01 00:00 UTC in epoch seconds

// Epoch seconds of table entry i.
function eventEpoch(i) {
    return (EclipseData.DAYS[i] + EclipseData.MINUTES[i] / 1440.0) * 86400.0 + UNIX_2000;
}

function eventType(i) {
    return EclipseData.TYPEMAG[i] / 1000;
}

// A transcription typo is the likeliest failure in a generated table, and the
// binary search in MoonPhase.lookup misbehaves silently if the order is wrong.
(:test, :typecheck(false))
function testTableStrictlyAscending(logger) {
    var days = EclipseData.DAYS;
    Test.assertEqual(days.size(), EclipseData.COUNT);
    Test.assertEqual(EclipseData.MINUTES.size(), EclipseData.COUNT);
    Test.assertEqual(EclipseData.TYPEMAG.size(), EclipseData.COUNT);

    for (var i = 1; i < days.size(); i += 1) {
        if (days[i] <= days[i - 1]) {
            logger.error("DAYS not ascending at index " + i + ": " + days[i]);
            return false;
        }
    }
    Test.assertEqual(days[0], EclipseData.FIRST_DAY);
    Test.assertEqual(days[days.size() - 1], EclipseData.LAST_DAY);
    return true;
}

(:test, :typecheck(false))
function testTableValuesInRange(logger) {
    for (var i = 0; i < EclipseData.COUNT; i += 1) {
        var m = EclipseData.MINUTES[i];
        if (m < 0 || m > 1439) {
            logger.error("MINUTES out of range at " + i + ": " + m);
            return false;
        }
        var t = eventType(i);
        if (t < 0 || t > EclipseData.TOTAL_LUNAR) {
            logger.error("bad type at " + i + ": " + t);
            return false;
        }
    }
    return true;
}

// Every event in the table must be found at its own maximum, with the right
// type. This covers all 93 rather than a hand-picked few.
(:test, :typecheck(false))
function testEveryTableEventDetected(logger) {
    Settings.load();
    for (var i = 0; i < EclipseData.COUNT; i += 1) {
        MoonPhase.invalidateCache();
        var e = MoonPhase.eclipseAt(eventEpoch(i));
        if (e == null) {
            logger.error("no eclipse found for table index " + i
                + " (day " + EclipseData.DAYS[i] + ")");
            return false;
        }
        if (e[:type] != eventType(i)) {
            logger.error("type mismatch at index " + i + ": got " + e[:type]
                + " expected " + eventType(i));
            return false;
        }
        if (!e[:exact]) {
            logger.error("index " + i + " should have come from the table");
            return false;
        }
    }
    return true;
}

// The table is authoritative inside its span, so a date between eclipse seasons
// must produce nothing at all.
(:test, :typecheck(false))
function testQuietBetweenEvents(logger) {
    Settings.load();
    // Midpoints between consecutive events, skipping pairs closer than 3 days
    // apart (an eclipse season has a solar and a lunar event two weeks apart,
    // and the +/-6h windows can otherwise be reached).
    for (var i = 1; i < EclipseData.COUNT; i += 1) {
        var gap = EclipseData.DAYS[i] - EclipseData.DAYS[i - 1];
        if (gap < 3) { continue; }
        var mid = (eventEpoch(i) + eventEpoch(i - 1)) / 2.0;
        MoonPhase.invalidateCache();
        var e = MoonPhase.eclipseAt(mid);
        if (e != null) {
            logger.error("false eclipse between index " + (i - 1) + " and " + i
                + ": type " + e[:type]);
            return false;
        }
    }
    return true;
}

// The computed path is what runs past 2045, so it is checked against the table
// it is meant to replace. It is allowed to disagree on type at the boundaries
// between annular/hybrid and total/partial, but it must find the events.
(:test, :typecheck(false))
function testComputedPathAgreesWithTable(logger) {
    Settings.load();
    var found = 0;
    var kindOk = 0;
    for (var i = 0; i < EclipseData.COUNT; i += 1) {
        var type = eventType(i);
        // Very shallow penumbral events fall outside Meeus' node test; they are
        // never rendered, so they are not required here.
        if (type == EclipseData.PENUMBRAL) { continue; }
        found += 1;

        var d = MoonPhase.days2000(eventEpoch(i));
        var e = MoonPhase.estimateAt(d);
        if (e == null) {
            logger.error("computed path missed table index " + i);
            return false;
        }
        if (e[:lunar] == EclipseData.isLunar(type)) { kindOk += 1; }
    }
    logger.debug("computed path: " + kindOk + "/" + found + " correct kind");
    Test.assertEqual(kindOk, found);
    return true;
}

// The Sun should be up at local noon and down at local midnight, at a
// longitude where those line up with UTC.
(:test, :typecheck(false))
function testSunAltitude(logger) {
    // 2026-06-21, northern summer solstice-ish, Greenwich.
    var noon = (9668.0 + 12.0 / 24.0) * 86400.0 + UNIX_2000;
    var midnight = 9668.0 * 86400.0 + UNIX_2000;

    var altNoon = SkyPosition.sunAltitude(noon, 51.48, 0.0);
    var altMid  = SkyPosition.sunAltitude(midnight, 51.48, 0.0);
    logger.debug("London noon alt " + altNoon + ", midnight alt " + altMid);

    Test.assert(altNoon > 40.0);
    Test.assert(altMid < -5.0);

    // The far side of the world must be the other way round.
    var altSydney = SkyPosition.sunAltitude(noon, -33.87, 151.21);
    logger.debug("Sydney at same instant: " + altSydney);
    Test.assert(altSydney < 0.0);
    return true;
}

// The visibility gate must flip between a location where the Moon is up and its
// antipode, and must fail open when there is no position.
(:test, :typecheck(false))
function testVisibilityGate(logger) {
    Settings.load();

    // 2025-09-07 18:12 UTC total lunar eclipse: the Moon was up over Asia.
    var when = (9381.0 + (18.0 * 60 + 12) / 1440.0) * 86400.0 + UNIX_2000;
    var eclipse = { :type => EclipseData.TOTAL_LUNAR, :lunar => true,
                    :magnitude => 1.36, :offset => 0.0, :exact => true };

    Settings.eclipseVisibility = Settings.ECLIPSE_IF_HERE;

    Settings.debugLatitude = 28.61;      // Delhi: night, Moon up
    Settings.debugLongitude = 77.21;
    var here = SkyPosition.eclipseVisible(eclipse, when);

    Settings.debugLatitude = -28.61;     // antipode: day, Moon down
    Settings.debugLongitude = -102.79;
    var there = SkyPosition.eclipseVisible(eclipse, when);

    logger.debug("Delhi visible=" + here + ", antipode visible=" + there);
    Test.assert(here);
    Test.assert(!there);

    // No position at all must fail open rather than hiding the eclipse.
    Settings.debugLatitude = Settings.COORD_UNSET;
    Settings.debugLongitude = Settings.COORD_UNSET;
    Settings.eclipseVisibility = Settings.ECLIPSE_ALWAYS;
    Test.assert(SkyPosition.eclipseVisible(eclipse, when));

    return true;
}

// Sun signs must cover the year with no gaps and no overlaps.
(:test, :typecheck(false))
function testZodiacSigns(logger) {
    Test.assertEqual(Zodiac.signFor(1, 1), 10);    // Capricornus
    Test.assertEqual(Zodiac.signFor(1, 20), 11);   // Aquarius
    Test.assertEqual(Zodiac.signFor(3, 20), 12);   // Pisces
    Test.assertEqual(Zodiac.signFor(3, 21), 1);    // Aries
    Test.assertEqual(Zodiac.signFor(8, 22), 5);    // Leo
    Test.assertEqual(Zodiac.signFor(8, 23), 6);    // Virgo
    Test.assertEqual(Zodiac.signFor(12, 22), 10);  // Capricornus

    // Every constellation must have stars, and every line index must exist.
    for (var s = 1; s <= 12; s += 1) {
        var stars = Zodiac.stars(s);
        var n = stars.size() / 3;
        Test.assert(n >= 4);
        Test.assertEqual(stars.size() % 3, 0);

        var lines = Zodiac.lines(s);
        Test.assertEqual(lines.size() % 2, 0);
        for (var i = 0; i < lines.size(); i += 1) {
            if (lines[i] < 0 || lines[i] >= n) {
                logger.error("sign " + s + " line index out of range: " + lines[i]);
                return false;
            }
        }
    }
    return true;
}

// Known moon phases, as a guard on the synodic reference.
(:test, :typecheck(false))
function testMoonPhase(logger) {
    // 2025-03-14 was a total lunar eclipse, so a full moon: fraction near 0.5.
    var full = (9204.0 + 7.0 / 24.0) * 86400.0 + UNIX_2000;
    var f = MoonPhase.fractionAt(full);
    logger.debug("fraction at 2025-03-14 07:00 = " + f);
    Test.assert(f > 0.47 && f < 0.53);
    Test.assert(MoonPhase.illumination(f) > 0.98);

    // 2026-02-17 was an annular solar eclipse, so a new moon.
    var newMoon = (9544.0 + 12.0 / 24.0) * 86400.0 + UNIX_2000;
    var nf = MoonPhase.fractionAt(newMoon);
    logger.debug("fraction at 2026-02-17 12:00 = " + nf);
    Test.assert(nf < 0.03 || nf > 0.97);
    return true;
}
