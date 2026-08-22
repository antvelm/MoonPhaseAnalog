using Toybox.Application;
using Toybox.WatchUi;

class MoonPhaseAnalogApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new MoonPhaseAnalogView() ];
    }

    // Settings are cached for the life of a draw loop, so both the cache and
    // the eclipse result have to be dropped when the user changes something.
    function onSettingsChanged() {
        Settings.invalidate();
        MoonPhase.invalidateCache();
        WatchUi.requestUpdate();
    }
}
