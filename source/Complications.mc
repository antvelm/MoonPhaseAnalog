using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Data lookups kept out of the drawing code. Every access is guarded so an
// unsupported device or missing reading degrades instead of crashing.
module Complications {

    // Day of the month, 1..31.
    function dayOfMonth() {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return info.day;
    }

    // Current heart rate in bpm, or null when nothing is available
    // (off wrist, or between optical samples in low power).
    function heartRate() {
        var info = Activity.getActivityInfo();
        if (info != null && (info has :currentHeartRate) && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }

        if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            if (it != null) {
                var sample = it.next();
                if (sample != null
                        && sample.heartRate != null
                        && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return sample.heartRate;
                }
            }
        }
        return null;
    }
}
