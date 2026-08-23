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
omarchy plugin add https://github.com/mic-kul/quakattro.git --enable
```

Then bind it in `~/.config/hypr/bindings.conf`:

```
bindd = SUPER SHIFT, Q, Quakattro, exec, omarchy-shell -q shell toggle quakattro
```

`omarchy plugin list` shows what is installed, and `omarchy plugin disable
quakattro` turns it off without removing it.

## Remove it

```sh
omarchy plugin remove quakattro
```

That disables the plugin in the running shell and deletes
`~/.config/omarchy/plugins/quakattro`. Two things it cannot do for you:

- **Delete the keybind.** Remove the `bindd` line you added from
  `~/.config/hypr/bindings.conf`, or the key will run a toggle for a plugin
  that is no longer there.
- **Reach outside its own directory.** Quakattro writes nothing anywhere else
  — no config, no save file, no cache — so once the directory and the keybind
  are gone, nothing of it remains.

If you installed it by hand instead, `rm -rf ~/.config/omarchy/plugins/quakattro`
and reload the shell.

## Build

Both generated files are committed; rebuild them only if you change the source.

```sh
tools/build-maze.py         # writes the map into raycast.frag and maze.js
bin/build                   # bakes raycast.frag -> .qsb (needs qt6-shadertools)
omarchy plugin validate .   # checks the manifest against the shell's own schema
```

Run them in that order; the maze builder edits the shader, so the bake has to
follow it. Both are idempotent: running them without changing anything leaves
no diff, which is the check worth putting in CI.

The maze generator seeds from a constant, so a given release always plays the
same maze. Pass a seed to get a different one.

GLSL has no `#include`, so the renderer's copy of the map cannot be a separate
file — it lives inside `raycast.frag` between two markers, and the generator
rewrites it there. That is the whole reason the generator touches the shader:
the map the renderer draws and the map collision believes have to be written
by the same program, or the first seed change gives you walls you can walk
through.

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
