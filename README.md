# Godot material free race

Reproduces [godotengine/godot#125309](https://github.com/godotengine/godot/issues/125309). With the Separate thread model, the render thread loops forever on two `SelfList` errors.

```
godot --path . -- --rate=3000
```

Four threads create `StandardMaterial3D`s while the main thread creates and drops a batch each frame. The run hangs within seconds and the errors never stop, so kill it.

| Option | Effect |
|---|---|
| `--rate=<n>` | Each creator makes n materials a second. Without it, the render command queue overflows after about 18 s. |
| `--control` | The threads create no material. |
| `--hold` | Keeps each material two frames before releasing it. |

## Results

Godot 4.7.2.stable.official [ed1daf0bf], Linux, Vulkan, Forward+. A clean run ends after 125 s.

| Build | Options | Result |
|---|---|---|
| official | `--rate=3000` | hangs as the threads start |
| official | `--rate=3000 --control` | clean |
| official | `--rate=3000 --hold` | clean |
| official, `--render-thread safe` | none | hung 1 of 1, after about 16 s |
| debug, unchanged | `--rate=3000` | hung 3 of 3 |
| debug, with the lock proposed in the issue | `--rate=3000` | clean 3 of 3 |

MIT license.
