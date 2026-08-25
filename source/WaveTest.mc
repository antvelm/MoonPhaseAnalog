using Toybox.Test;
using Toybox.Time;
using Toybox.Application;
using Toybox.Lang;

// Unit tests for the rainbow wave's schedule.
//
// Run with:  powershell -File tools\run-tests.ps1
//
// The slot key is built from Time.today(), which is the epoch second of *local*
// midnight -- verified on device settings of UTC+2, where today % 86400 came
// back as 79200 (22:00 UTC). That is what makes "today + slot" rise monotonically
// across days, and these tests pin the behaviour that depends on it.

class WaveClock {
    var hour;
    var sec;
    function initialize(h) { hour = h; sec = 30; }
}

(:test, :typecheck(false))
function testWaveSlotsAcrossTheDay(logger) {
    Settings.load();
    Application.Storage.deleteValue(RainbowWave.STORAGE_KEY);

    // Walk a whole day an hour at a time, letting each wave run to completion,
    // and check the wave lands on exactly the WaveIntervalHours slots.
    var fired = [];
    for (var h = 0; h < 24; h += 1) {
        var clock = new WaveClock(h);
        var t = h * 3600;
        RainbowWave.update(t, clock, true);
        if (RainbowWave.isActive()) { fired.add(h); }
        RainbowWave.update(t + RainbowWave.DURATION_SEC + 1, clock, true);
    }

    logger.debug("fired at hours: " + fired.toString());
    Test.assertEqual(fired.size(), 24 / Settings.waveIntervalHours);
    for (var i = 0; i < fired.size(); i += 1) {
        Test.assertEqual(fired[i], Settings.waveHour + i * Settings.waveIntervalHours);
    }
    return true;
}

// The watch wakes on any arm movement, so a wave cut short by the screen going
// back to sleep must not spend its slot: the next raise has to replay it.
(:test, :typecheck(false))
function testInterruptedWaveReplays(logger) {
    Settings.load();
    Application.Storage.deleteValue(RainbowWave.STORAGE_KEY);
    var clock = new WaveClock(Settings.waveHour);

    RainbowWave.update(0, clock, true);
    Test.assert(RainbowWave.isActive());
    RainbowWave.update(3, clock, true);          // a few frames in...
    RainbowWave.update(4, clock, false);         // ...and the watch sleeps

    Test.assert(Application.Storage.getValue(RainbowWave.STORAGE_KEY) == null);

    RainbowWave.update(100, clock, true);        // next wrist raise
    Test.assert(RainbowWave.isActive());
    RainbowWave.update(100 + RainbowWave.DURATION_SEC + 1, clock, true);

    // Seen through this time, so the slot is spent and does not come back.
    Test.assertEqual(Application.Storage.getValue(RainbowWave.STORAGE_KEY),
                     Time.today().value());
    RainbowWave.update(200, clock, true);
    Test.assert(!RainbowWave.isActive());
    return true;
}

// ...but a watch whose wake window is always shorter than the wave must not
// retry for ever.
(:test, :typecheck(false))
function testReplayIsCapped(logger) {
    Settings.load();
    Application.Storage.deleteValue(RainbowWave.STORAGE_KEY);
    var clock = new WaveClock(Settings.waveHour);

    var t = 0;
    for (var i = 0; i < RainbowWave.MAX_ATTEMPTS; i += 1) {
        RainbowWave.update(t, clock, true);
        Test.assert(RainbowWave.isActive());
        RainbowWave.update(t + 2, clock, true);
        RainbowWave.update(t + 3, clock, false);
        t += 100;
    }

    Test.assertEqual(Application.Storage.getValue(RainbowWave.STORAGE_KEY),
                     Time.today().value());
    RainbowWave.update(t, clock, true);
    Test.assert(!RainbowWave.isActive());
    return true;
}
