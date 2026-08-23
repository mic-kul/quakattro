import QtQuick
import "maze.js" as Maze

// The game itself, with no opinion about the surface it is drawn on. The
// standalone runner puts it in a Window; the Omarchy plugin puts it in a
// layer-shell overlay.
FocusScope {
    id: root

    // False while the overlay is closed, which stops the frame loop dead.
    property bool active: false
    signal exitRequested()

    // omawrite ships iA Writer Mono S; nobody else has to.
    //
    // QML's font value type has no "families" -- that is C++-only API -- so the
    // list has to be walked by hand, and Qt.fontFamilies() enumerates every
    // installed family to do it, about 27ms. That is paid once when you summon
    // the game, not at shell startup, because the manifest asks not to be kept
    // loaded.
    readonly property string mono: {
        var wanted = ["iA Writer Mono S", "JetBrainsMono Nerd Font", "JetBrains Mono",
                      "Fira Code", "Hack", "DejaVu Sans Mono", "monospace"];
        var have = Qt.fontFamilies();
        for (var i = 0; i < wanted.length; ++i)
            if (have.indexOf(wanted[i]) !== -1)
                return wanted[i];
        return "monospace";
    }

    Rectangle { anchors.fill: parent; color: "black" }

    property real posX: Maze.START[0]
    property real posY: Maze.START[1]
    property real dirX: 1.0
    property real dirY: 0.0
    property real planeX: 0.0
    property real planeY: 0.66
    property real torch: 1.0
    property real fps: 0

    property var held: ({})
    property var apples: []
    property var merchants: []
    property int eaten: 0
    property int complexity: 0
    readonly property int merchantSlots: 3
    readonly property int merchantsLeft: merchants.length - complexity
    property bool won: false
    property bool dead: false
    property bool helpOpen: false
    property string flash: ""

    property bool consoleOpen: false
    property var consoleLog: []
    property bool godmode: false
    property var route: []
    property real replan: 0

    readonly property color ink: "#c8b48a"
    readonly property var grailMarker: ({ x: Maze.GRAIL[0], y: Maze.GRAIL[1], alive: 1, phase: 0.4 })

    // Seconds left on each effect. Long enough to feel, short enough that
    // neither one decides the run.
    readonly property real effectSeconds: 10.0
    property real lighter: 0
    property real heavier: 0

    // Put something down and you move twice as fast. Get sold a cloud and you
    // carry it at a quarter pace.
    readonly property real pace: (lighter > 0 ? 2.0 : 1.0) / (heavier > 0 ? 4.0 : 1.0)
    readonly property bool paused: helpOpen || consoleOpen || won || dead

    // ---- maze -------------------------------------------------------------

    function solidCell(cx, cy) {
        if (cx < 0 || cx >= Maze.N || cy < 0 || cy >= Maze.N)
            return true;
        return ((Maze.ROWS[cy] >> cx) & 1) !== 0;
    }

    function solid(x, y) { return solidCell(Math.floor(x), Math.floor(y)); }

    // Every open cell, worked out once. Rejection sampling for a spot far from
    // the player used to be a while(true), which is a poor thing to run inside
    // a desktop shell: a maze with nowhere far enough away would hang it.
    readonly property var floorCells: {
        var out = [];
        for (var y = 0; y < Maze.N; ++y)
            for (var x = 0; x < Maze.N; ++x)
                if (!solidCell(x, y))
                    out.push([x + 0.5, y + 0.5]);
        return out;
    }

    function openCell() {
        var fallback = floorCells[0];
        for (var tries = 0; tries < 24; ++tries) {
            var c = floorCells[Math.floor(Math.random() * floorCells.length)];
            if (Math.abs(c[0] - posX) + Math.abs(c[1] - posY) > 6)
                return c;
            fallback = c;
        }
        return fallback;
    }

    // Try each axis separately so a wall slides you along instead of stopping you.
    function slide(who, dx, dy, pad) {
        if (!solid(who.x + dx + Math.sign(dx) * pad, who.y)) who.x += dx;
        if (!solid(who.x, who.y + dy + Math.sign(dy) * pad)) who.y += dy;
    }

    function turn(a) {
        var c = Math.cos(a), s = Math.sin(a);
        var ndx = dirX * c - dirY * s;
        dirY = dirX * s + dirY * c; dirX = ndx;
        var npx = planeX * c - planeY * s;
        planeY = planeX * s + planeY * c; planeX = npx;
    }

    function reset() {
        posX = Maze.START[0]; posY = Maze.START[1];
        dirX = 1; dirY = 0; planeX = 0; planeY = 0.66;
        eaten = 0; complexity = 0; won = false; dead = false; flash = ""; route = [];
        lighter = 0; heavier = 0;
        var a = [];
        for (var i = 0; i < Maze.APPLES.length; ++i)
            a.push({ x: Maze.APPLES[i][0], y: Maze.APPLES[i][1], alive: 1, phase: i * 1.7 });
        apples = a.slice();
        var m = [];
        for (var j = 0; j < merchantSlots; ++j) {
            var c = openCell();
            m.push({ x: c[0], y: c[1], alive: 1, phase: j * 2.3 });
        }
        merchants = m.slice();
    }

    Component.onCompleted: reset()

    // Where a billboard lands on screen: xy centre, z half-size, w depth.
    // w <= 0 means gone, or behind the camera, and the shader skips it.
    readonly property vector4d nowhere: Qt.vector4d(0, 0, 0, -1)

    function billboard(o, radius) {
        if (!o || o.alive < 0.5)
            return nowhere;

        var relX = o.x - posX, relY = o.y - posY;
        var invDet = 1.0 / (planeX * dirY - dirX * planeY);
        var depth = invDet * (-planeY * relX + planeX * relY);
        if (depth < 0.12)
            return nowhere;

        var tx = invDet * (dirY * relX - dirX * relY);
        var bob = 0.05 * Math.sin(o.phase + torch * 3.0);
        return Qt.vector4d(0.5 * (1.0 + tx / depth),
                           0.5 + (0.14 + bob) / depth,
                           radius / depth,
                           depth);
    }

    // ---- autopilot --------------------------------------------------------

    // Breadth-first over the grid. The maze is 441 cells, so the naive queue is
    // not worth improving.
    function findRoute(sx, sy, tx, ty, avoid) {
        var key = function (x, y) { return y * Maze.N + x; };
        var seen = {}, prev = {}, queue = [[sx, sy]];
        seen[key(sx, sy)] = true;
        var steps = [[1, 0], [-1, 0], [0, 1], [0, -1]];
        while (queue.length > 0) {
            var cur = queue.shift();
            if (cur[0] === tx && cur[1] === ty) {
                var path = [], c = cur;
                while (!(c[0] === sx && c[1] === sy)) {
                    path.unshift(c);
                    c = prev[key(c[0], c[1])];
                }
                return path;
            }
            for (var i = 0; i < 4; ++i) {
                var nx = cur[0] + steps[i][0], ny = cur[1] + steps[i][1];
                if (solidCell(nx, ny) || seen[key(nx, ny)]) continue;
                if (avoid && avoid[key(nx, ny)]) continue;
                seen[key(nx, ny)] = true;
                prev[key(nx, ny)] = cur;
                queue.push([nx, ny]);
            }
        }
        return null;
    }

    function plan() {
        // Merchants poison the cells around them. If that walls us in, take the
        // straight route and accept the toll.
        var avoid = {};
        for (var i = 0; i < merchants.length; ++i) {
            if (!merchants[i].alive)
                continue;
            var mx = Math.floor(merchants[i].x), my = Math.floor(merchants[i].y);
            for (var dx = -1; dx <= 1; ++dx)
                for (var dy = -1; dy <= 1; ++dy)
                    avoid[(my + dy) * Maze.N + (mx + dx)] = true;
        }

        var target = null, best = 1e9;
        for (var j = 0; j < apples.length; ++j) {
            if (!apples[j].alive) continue;
            var d = Math.abs(apples[j].x - posX) + Math.abs(apples[j].y - posY);
            if (d < best) { best = d; target = apples[j]; }
        }
        if (!target)
            target = { x: Maze.GRAIL[0], y: Maze.GRAIL[1] };

        var sx = Math.floor(posX), sy = Math.floor(posY);
        var tx = Math.floor(target.x), ty = Math.floor(target.y);
        var r = findRoute(sx, sy, tx, ty, avoid);
        if (!r) r = findRoute(sx, sy, tx, ty, null);
        route = r ? r : [];
    }

    function autopilot(dt) {
        replan -= dt;
        if (replan <= 0 || route.length === 0) {
            plan();
            replan = 0.25;
        }
        if (route.length === 0)
            return;

        var wx = route[0][0] + 0.5, wy = route[0][1] + 0.5;
        if (Math.hypot(wx - posX, wy - posY) < 0.3) {
            route.shift();
                if (route.length === 0)
                return;
            wx = route[0][0] + 0.5; wy = route[0][1] + 0.5;
        }

        var want = Math.atan2(wy - posY, wx - posX);
        var have = Math.atan2(dirY, dirX);
        var diff = want - have;
        while (diff > Math.PI) diff -= 2 * Math.PI;
        while (diff < -Math.PI) diff += 2 * Math.PI;

        var rate = 3.4 * dt;
        turn(Math.max(-rate, Math.min(rate, diff)));

        // Slow into the corners rather than grinding along the wall.
        var speed = 3.0 * root.pace * dt * Math.max(0.15, 1.0 - Math.abs(diff) / 1.4);
        var me = { x: posX, y: posY };
        slide(me, dirX * speed, dirY * speed, 0.2);
        posX = me.x; posY = me.y;
    }

    // ---- console ----------------------------------------------------------

    function say(line) {
        var l = consoleLog.slice(-9);
        l.push(line);
        consoleLog = l;
    }

    function runCommand(raw) {
        var cmd = raw.trim().toLowerCase();
        if (cmd === "") return;
        say("] " + raw);
        if (cmd === "/godmode") {
            godmode = !godmode;
            route = [];
            say(godmode ? "godmode on — hands off the keyboard"
                        : "godmode off — you are on your own");
        } else if (cmd === "/reset") {
            reset(); say("maze reset");
        } else if (cmd === "/where") {
            say("you are at " + posX.toFixed(1) + ", " + posY.toFixed(1)
                + "; the grail is at " + Maze.GRAIL[0] + ", " + Maze.GRAIL[1]);
        } else if (cmd === "/help") {
            say("/godmode  play itself   /reset  start over");
            say("/where    position      /help   this");
        } else {
            say("unknown command: " + cmd + "  (try /help)");
        }
    }

    // ---- render -----------------------------------------------------------

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "raycast.frag.qsb"
        // Without this a bad or missing .qsb is a black fullscreen surface that
        // holds the keyboard and refuses the mouse on purpose. Hand it back.
        onStatusChanged: {
            if (status === ShaderEffect.Error) {
                console.warn("quakattro: shader failed to load\n" + log);
                root.exitRequested();
            }
        }
        property real posX: root.posX
        property real posY: root.posY
        property real dirX: root.dirX
        property real dirY: root.dirY
        property real planeX: root.planeX
        property real planeY: root.planeY
        property real torch: root.torch
        property vector4d apple0: root.billboard(root.apples[0], 0.13)
        property vector4d apple1: root.billboard(root.apples[1], 0.13)
        property vector4d apple2: root.billboard(root.apples[2], 0.13)
        property vector4d apple3: root.billboard(root.apples[3], 0.13)
        property vector4d apple4: root.billboard(root.apples[4], 0.13)
        property vector4d apple5: root.billboard(root.apples[5], 0.13)
        property vector4d apple6: root.billboard(root.apples[6], 0.13)
        property vector4d apple7: root.billboard(root.apples[7], 0.13)
        property vector4d grail: root.billboard(root.grailMarker, 0.20)
        property vector4d merchant0: root.billboard(root.merchants[0], 0.26)
        property vector4d merchant1: root.billboard(root.merchants[1], 0.26)
        property vector4d merchant2: root.billboard(root.merchants[2], 0.26)
    }

    // The mouse is not an input device here. Using one ends the run.
    //
    // It has to be a deliberate press, though. Focusing a window synthesises
    // one, and having the window manager end your game for you is not the
    // joke. So the trap only arms once the pointer has actually moved inside
    // the window, which a person does and a focus event does not.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        // Arm on displacement, never on a timer. A hovered surface receives a
        // position when the pointer merely enters it under a still cursor, and
        // focusing a window synthesises a press -- neither is a person reaching
        // for the mouse, and a stopwatch cannot tell the difference.
        property real lastX: -1
        property real lastY: -1
        property bool pointerMoved: false
        onPositionChanged: function (event) {
            if (lastX >= 0 && Math.abs(event.x - lastX) + Math.abs(event.y - lastY) > 8)
                pointerMoved = true;
            lastX = event.x;
            lastY = event.y;
        }
        onPressed: function (event) {
            if (!root.won && pointerMoved)
                root.dead = true;
            event.accepted = true;
        }
    }

    FrameAnimation {
        // Never runs while the overlay is closed. This lives inside the
        // Omarchy shell process; a game rendering in the background would
        // burn a core behind your bar.
        running: root.active && !root.paused
        onTriggered: {
            try {
                root.step(frameTime, elapsedTime);
            } catch (e) {
                // Logging this every frame for the life of the session is the
                // real hazard inside a shell, not the throw itself.
                console.warn("quakattro: stopping after an error in the frame loop\n" + e);
                running = false;
                root.exitRequested();
            }
        }
    }

    function step(frameTime, elapsedTime) {
            var dt = Math.min(frameTime, 0.05);
            root.fps = root.fps * 0.9 + (1 / Math.max(frameTime, 1e-4)) * 0.1;
            root.torch = 0.94 + 0.06 * Math.sin(elapsedTime * 13)
                             + 0.03 * Math.sin(elapsedTime * 41);
            root.lighter = Math.max(0, root.lighter - dt);
            root.heavier = Math.max(0, root.heavier - dt);

            if (root.godmode) {
                root.autopilot(dt);
            } else {
                var speed = (held[Qt.Key_Shift] ? 4.6 : 2.7) * root.pace * dt;
                var rot = 2.1 * dt;
                var me = { x: root.posX, y: root.posY };
                if (held[Qt.Key_W]) root.slide(me, root.dirX * speed, root.dirY * speed, 0.2);
                if (held[Qt.Key_S]) root.slide(me, -root.dirX * speed, -root.dirY * speed, 0.2);
                if (held[Qt.Key_A]) root.slide(me, root.dirY * speed, -root.dirX * speed, 0.2);
                if (held[Qt.Key_D]) root.slide(me, -root.dirY * speed, root.dirX * speed, 0.2);
                root.posX = me.x; root.posY = me.y;
                if (held[Qt.Key_Left]) root.turn(-rot);
                if (held[Qt.Key_Right]) root.turn(rot);
            }

            var a = root.apples, ate = false;
            for (var i = 0; i < a.length; ++i) {
                if (a[i].alive && Math.hypot(a[i].x - root.posX, a[i].y - root.posY) < 0.45) {
                    a[i].alive = 0; root.eaten++; ate = true;
                    root.lighter = root.effectSeconds;
                    root.flash = "simplicity +1 — lighter on your feet";
                    root.route = [];
                }
            }
            if (ate) root.apples = a.slice();

            var m = root.merchants;
            for (var j = 0; j < m.length; ++j) {
                if (!m[j].alive)
                    continue;
                var toX = root.posX - m[j].x, toY = root.posY - m[j].y;
                var d = Math.hypot(toX, toY) || 1;
                root.slide(m[j], (toX / d) * 1.35 * dt, (toY / d) * 1.35 * dt, 0.25);
                if (d < 0.55) {
                    // It made its sale. It has nothing else to offer, so it
                    // goes, and what you were carrying stays carried.
                    root.complexity++;
                    root.heavier = root.effectSeconds;
                    root.flash = "a merchant sold you the cloud — now carry it";
                    root.posX -= (toX / d) * 0.7; root.posY -= (toY / d) * 0.7;
                    m[j].alive = 0;
                    root.route = [];
                }
            }
            root.merchants = m.slice();

            if (Math.hypot(Maze.GRAIL[0] - root.posX, Maze.GRAIL[1] - root.posY) < 0.6) {
                if (root.eaten === a.length)
                    root.won = true;
                else
                    root.flash = "the grail is not for the cluttered — "
                              + (a.length - root.eaten) + " apples remain";
            }
    }

    Timer { interval: 2200; running: root.flash !== ""; onTriggered: root.flash = "" }

    Item {
        anchors.fill: parent
        focus: !root.consoleOpen
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_QuoteLeft || e.key === Qt.Key_AsciiTilde) {
                root.consoleOpen = true;
            } else if (e.key === Qt.Key_Question || e.key === Qt.Key_F1 || e.key === Qt.Key_Slash) {
                root.helpOpen = !root.helpOpen;
            } else if (e.key === Qt.Key_Escape) {
                if (root.helpOpen) root.helpOpen = false; else root.exitRequested();
            } else if (e.key === Qt.Key_R && (root.won || root.dead)) {
                root.reset();
            } else {
                held[e.key] = true;
            }
            e.accepted = true;
        }
        Keys.onReleased: function (e) { held[e.key] = false; e.accepted = true; }
    }

    // ---- chrome -----------------------------------------------------------

    Text {
        x: 16; y: 12
        color: root.ink
        font.family: root.mono; font.pixelSize: 14
        lineHeight: 1.35
        text: "apples  " + root.eaten + " / " + root.apples.length
              + "\ncomplexity  " + root.complexity
              + "\nmerchants  " + root.merchantsLeft
              + "\npace  " + root.pace.toFixed(2) + "x"
                    + (root.lighter > 0 ? "  light " + Math.ceil(root.lighter) + "s" : "")
                    + (root.heavier > 0 ? "  heavy " + Math.ceil(root.heavier) + "s" : "")
              + "\n" + Math.round(root.fps) + " fps"
    }

    Text {
        anchors.right: parent.right; anchors.rightMargin: 16; y: 12
        color: root.ink; opacity: 0.5
        font.family: root.mono; font.pixelSize: 12
        horizontalAlignment: Text.AlignRight
        text: (root.godmode ? "AUTOPLAY\n" : "") + "~  console      ?  help"
        visible: !root.won
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 64
        color: root.ink
        opacity: root.flash === "" ? 0 : 0.9
        Behavior on opacity { NumberAnimation { duration: 250 } }
        font.family: root.mono; font.pixelSize: 15
        text: root.flash
    }

    // Quake's console dropped from the top. So does this one.
    Rectangle {
        id: consolePane
        width: parent.width
        height: parent.height * 0.44
        y: root.consoleOpen ? 0 : -height
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        color: "#0a0c10"
        opacity: 0.94
        border.color: "#2a2f38"

        Text {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: prompt.top }
            anchors.margins: 14
            color: root.ink
            font.family: root.mono; font.pixelSize: 13
            lineHeight: 1.4
            verticalAlignment: Text.AlignBottom
            wrapMode: Text.Wrap
            text: root.consoleLog.join("\n")
        }

        Row {
            id: prompt
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.margins: 14
            spacing: 8
            Text {
                text: "]"; color: root.ink
                font.family: root.mono; font.pixelSize: 14
            }
            TextInput {
                id: entry
                width: parent.width - 30
                color: root.ink
                font.family: root.mono; font.pixelSize: 14
                focus: root.consoleOpen
                onAccepted: { root.runCommand(text); text = ""; }
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_QuoteLeft || e.key === Qt.Key_AsciiTilde
                            || e.key === Qt.Key_Escape) {
                        root.consoleOpen = false;
                        e.accepted = true;
                    }
                }
            }
        }
        Component.onCompleted: root.say("Quakattro console. /help for commands.")
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"; opacity: 0.82
        visible: root.helpOpen
        Text {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 620)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.ink
            font.family: root.mono; font.pixelSize: 16
            lineHeight: 1.5
            text: "QUAKATTRO\n\n"
                + "W A S D     move\n"
                + "← →         turn\n"
                + "Shift       run\n"
                + "~           console\n"
                + "?  /  F1    this help\n"
                + "Esc         close, then quit\n\n"
                + "The mouse is not an input device here.\n\n"
                + "An apple makes you twice as fast for ten seconds.\n"
                + "A cloud makes you four times slower for ten.\n\n"
                + "Eat every apple. Each one is a thing you no longer need.\n"
                + "Avoid the merchants of complexity — they will sell you\n"
                + "the cloud, and you will drop what you were carrying.\n\n"
                + "The grail is Linux on the desktop. It is at the far end,\n"
                + "and it does not open for the cluttered."
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.dead
        color: "#140607"
        Text {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 620)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#e0736a"
            font.family: root.mono; font.pixelSize: 22
            lineHeight: 1.6
            textFormat: Text.RichText
            // RichText ignores newlines; it wants <br>.
            text: "YOU TOUCHED THE MOUSE<br><br>"
                + "<font size=\"3\">no mouse. it's Omarchy.<br><br>"
                + "the grail was " + Math.round(Math.hypot(Maze.GRAIL[0] - root.posX,
                                                           Maze.GRAIL[1] - root.posY))
                + " squares away<br><br>R&nbsp;&nbsp;again</font>"
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.won
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0b0d10" }
            GradientStop { position: 1.0; color: "#2a1f0c" }
        }
        Text {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 620)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#f0d68c"
            font.family: root.mono; font.pixelSize: 22
            lineHeight: 1.6
            textFormat: Text.RichText
            text: "LINUX ON THE DESKTOP<br><br>"
                + "<font size=\"3\">you took on " + root.complexity + " complexity"
                + " on the way<br><br>"
                + (root.complexity === 0
                   ? "not one merchant sold you anything"
                   : "next time, take the long way round") + "<br><br>R&nbsp;&nbsp;again</font>"
        }
    }
}
