# Quakattro

A raycaster for [Omarchy Quattro](https://omarchy.org). The walls are tiled
with your window manager's dwindle layout, the enemies are merchants of
complexity, and the holy grail is Linux on the desktop.

Eat every apple. Each one is a thing you no longer need, and putting it down
makes you twice as fast for ten seconds. The merchants sell you the cloud;
carrying one makes you four times slower for ten. A merchant that has made its
sale is done and leaves. The grail does not open for the cluttered.

There is no mouse. Clicking one ends the run.

## Run it

```sh
qml6 Standalone.qml
```

An ordinary window. `?` or `F1` for help, `~` for the console.

| | |
|---|---|
| `W A S D` | move |
| `←` `→` | turn |
| `Shift` | run |
| `~` | console |
| `?` `F1` | help |
| `Esc` | close, then leave |

Console commands: `/godmode` plays it for you, breadth-first through the maze
and around the merchants; `/reset`, `/where`, `/help`.

## Install as an Omarchy plugin

```sh
git clone https://github.com/mic-kul/quakattro ~/.config/omarchy/plugins/quakattro
omarchy-shell shell listPlugins        # it should be listed
```

Bind it in `~/.config/hypr/bindings.conf`:

```
bindd = SUPER SHIFT, Q, Quakattro, exec, omarchy-shell -q shell toggle quakattro
```

Plugins share the long-running Omarchy shell process, so two things matter and
both are handled here: the frame loop stops dead when the overlay is closed
(`active: root.opened`), and `Esc` calls `dismiss()` rather than quitting —
`Qt.quit()` in a plugin would take down your bar, notifications, OSD and lock
screen with it.

Test in a nested Hyprland before pointing it at your live session.

## Build

Both generated files are committed; rebuild them only if you change the source.

```sh
bin/build              # bakes raycast.frag -> raycast.frag.qsb (needs qt6-shadertools)
tools/build-maze.py    # regenerates maze.glsl and maze.js together
```

The maze generator seeds from a constant, so a given release always plays the
same maze. Pass a seed to get a different one. It writes both files in one go
because the shader and the collision have to agree about where the walls are.

## How it works

The whole renderer is one fragment shader. Per-pixel DDA against a 21×21 bitmask
maze, floor and ceiling cast from mirrored row distance, torchlight falling off
as `1 / (1 + d²)`. Apples, merchants and the grail are billboards drawn as
signed-distance fields — no textures, no meshes, no assets.

The walls are Hyprland's dwindle layout: eleven levels of recursive halving,
alternating axis, each split leaving one pane behind and carrying on with the
other, so the pattern spirals into a corner the way your windows do. Gap width
scales with pane size, or the deepest panes would vanish into their own gaps.

## Licence

MIT.
