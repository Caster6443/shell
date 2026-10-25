import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.Multimedia
import Caelestia.Shaders
import Caelestia.State
import qs.services
import "WallpaperTransitionPolicy.js" as TransitionPolicy

Item {
    id: root

    readonly property var transitionNames: TransitionPolicy.names(Shaders)
    property string activeTransition: "crossfade"
    readonly property transitionShader shader: Shaders[activeTransition] ?? Shaders.crossfade

    function selectTransition(): void {
        const configured = CUtils.enumToString(Config.background, "wallpaperTransition");
        activeTransition = TransitionPolicy.pick(configured, transitionNames, activeTransition, Math.random(), Config.background.wallpaperTransitionRandomEffects);
    }

    property string source: Wallpapers.current
    property ShaderEffectSource currentCapture: capture1
    property real transitionProgress: 1

    onSourceChanged: {
        transitionAnim.stop();

        if (transitionProgress < 1) {
            currentCapture = currentCapture === capture1 ? capture2 : capture1;
            currentCapture.sourceItem = transition;
        } else {
            currentCapture.sourceItem = live;
        }

        currentCapture.visible = true;
        currentCapture.scheduleUpdate();
    }

    Component.onCompleted: {
        // The initial frame is not a wallpaper change; do not consume a random pick.
        const configured = CUtils.enumToString(Config.background, "wallpaperTransition");
        if (configured !== "Random")
            selectTransition();
        live.source = source;
    }

    NumberAnimation on transitionProgress {
        id: transitionAnim

        running: false
        duration: root.shader.duration * Tokens.anim.durations.scale
        easing: root.shader.easing
        to: 1
    }

    ShaderEffectSource {
        id: capture1

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            // Capture an in-flight transition with its original shader first.
            root.selectTransition();
            live.source = root.source;
            if (live.ready)
                transitionAnim.start();
        }
    }

    ShaderEffectSource {
        id: capture2

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            // Capture an in-flight transition with its original shader first.
            root.selectTransition();
            live.source = root.source;
            if (live.ready)
                transitionAnim.start();
        }
    }

    Visual {
        id: live

        anchors.fill: parent
        playing: PersistentState.wallpaperPlaying
        animate: false
        layer.enabled: true

        onReadyChanged: {
            if (ready && source === root.source)
                transitionAnim.start();
        }
    }

    ShaderEffect {
        id: transition

        property Item from
        property Item to: live
        property real progress: root.transitionProgress

        anchors.fill: parent
        visible: root.transitionProgress < 1
        fragmentShader: root.shader.url
    }
}
