using Toybox.Graphics as Gfx;
using Toybox.System;

// Optional on-screen performance overlay: a per-section breakdown of onUpdate
// plus live heap use.
//
// It costs 62 bytes of data and no code at all in a normal build (measured
// against the same build with this file deleted). Every entry point exists
// twice -- a real (:perf) version and an empty (:noperf) stub -- and exactly
// one of those annotations is excluded at compile time, so the unused half
// never reaches the .prg and the optimiser drops the empty calls.
//
// monkey.jungle excludes :perf by default, which is what keeps every other
// build script (package.ps1, tools\gen-*.ps1, a bare monkeyc) working
// unchanged. perf.jungle flips the exclusion to :noperf and is layered on top
// by `.\build.ps1 -Perf` and `.\run-simulator.ps1 -Perf`.
//
// Reading the overlay: one line per section of onUpdate showing the
// milliseconds that section cost in the frame just drawn, then a total as
// "cur/peak ms" and the live heap in kB.
//
// A watch face's onUpdate runs once per second while the screen is awake, so
// the total is also a CPU duty cycle: 60ms is 6% of every waking second, and
// that percentage is what the battery pays. The hard ceiling is not time at
// all -- Connect IQ's watchdog counts VM instructions, 240,000 per callback
// on a Venu 3 (see the SDK's Devices\venu3\simulator.json) -- but a face that
// is slow in milliseconds is heading for that limit too.
//
// A Venu 3 watch face gets 128kB for code, data and heap combined; build.ps1
// prints the static half, and the kB here is what is live on top of it.
module Perf {

    // One label per mark() call, in the order onUpdate makes them. Reordering
    // or adding a mark() means editing this list to match: the pairing is
    // positional, which keeps mark() down to a subtraction and a store.
    (:perf) const SECTIONS = [
        "setup",    // Settings.load + refreshCaches
        "phase",    // MoonPhase.fractionAt
        "wave",     // RainbowWave.setup + update
        "clear",    // dc.clear
        "bg",       // Dial.drawBackground + orbit ring
        "track",    // Dial.drawSecondTrack
        "marks",    // Dial.drawHourMarks
        "cplx",     // date + heart rate
        "moon",     // moon subdial
        "hands"     // Hands
    ];

    // Drawn from above the centre downwards, clear of the hour numerals at
    // 0.76R and of the date, heart rate and moon complications.
    (:perf) const Y_FRACTION = 0.22;
    (:perf) const FONT       = Gfx.FONT_XTINY;
    (:perf) const COLOR      = 0x00FF00;   // deliberately ugly; never ships

    (:perf) var _times = null;
    (:perf) var _slot = 0;
    (:perf) var _t0 = 0;
    (:perf) var _last = 0;
    (:perf) var _peak = 0;

    // Call as the first statement of onUpdate.
    (:perf)
    function begin() {
        if (_times == null) { _times = new [SECTIONS.size()]; }
        _t0 = System.getTimer();
        _last = _t0;
        _slot = 0;
    }

    (:noperf)
    function begin() {
    }

    // Call after each section of onUpdate, in the order SECTIONS lists them.
    // Charges everything since the previous mark to the next slot.
    (:perf, :typecheck(false))
    function mark() {
        var now = System.getTimer();
        if (_slot < _times.size()) { _times[_slot] = now - _last; }
        _slot++;
        _last = now;
    }

    (:noperf)
    function mark() {
    }

    // Call as the last statement of onUpdate, so the total covers every other
    // draw. The overlay's own cost is left out, which is what we want: it is
    // not part of what ships.
    (:perf, :typecheck(false))
    function draw(dc) {
        var total = System.getTimer() - _t0;
        if (total > _peak) { _peak = total; }

        var w = dc.getWidth();
        var lineHeight = dc.getFontHeight(FONT);
        var y = dc.getHeight() * Y_FRACTION;

        dc.setColor(COLOR, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < SECTIONS.size(); i++) {
            var ms = (_times[i] == null) ? 0 : _times[i];
            // Skip the noise: a section under a millisecond is not the one
            // worth chasing, and dropping it keeps the list short enough to
            // read on the wrist.
            if (ms <= 0) { continue; }
            dc.drawText(w / 2, y, FONT, SECTIONS[i] + " " + ms,
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            y += lineHeight;
        }

        var used = System.getSystemStats().usedMemory;
        dc.drawText(w / 2, y, FONT,
                    total + "/" + _peak + "ms  " + (used / 1024) + "k",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    (:noperf)
    function draw(dc) {
    }
}
