# Godot material free race

A small Godot 4 project that reproduces the hang reported in [godotengine/godot#125309](https://github.com/godotengine/godot/issues/125309). With the Separate thread model the render thread loops forever on two `SelfList` errors, and the main thread waits in `RenderingServerDefault::sync()`.

## What it does

Four threads create `StandardMaterial3D`s and ask for their RIDs. Each frame the main thread creates a batch of materials, sets a parameter on each and drops them in the same frame. The render thread then frees materials that are still in its update list while the other threads add to that list.

## Run it

```
godot --path . -- --rate=3000
```

`project.godot` sets `rendering/driver/threads/thread_model` to Separate. A run lasts 125 seconds. The first 5 warm up, and the next 120 create and drop materials. The project prints one `beat` line a second.

When it hangs, the `beat` lines stop and the output fills with this pair:

```
ERROR: Condition "p_elem->_root != this" is true.
   at: remove (./core/templates/self_list.h:80)
ERROR: Condition "p_elem->_root" is true.
   at: add (./core/templates/self_list.h:46)
```

Kill the process then. The errors never stop, and the output grows by several gigabytes in ten minutes.

## Options

Pass them after `--`.

| Option | Effect |
|---|---|
| `--rate=<n>` | Each thread and the main thread create n materials a second. Without it they create up to 300 a frame. A run that does not hang then fills the render command queue past 4 GiB in about 18 seconds and ends on an unrelated `LocalVector` index error. |
| `--control` | The threads create no material. The main thread still creates and drops its batch. |
| `--hold` | The project keeps every material until two process frames have passed since its last change, then releases it on the main thread. |

## Results

Godot 4.7.2.stable.official [ed1daf0bf] and debug builds of the same commit, on Linux with Vulkan and Forward+. Each run lasts 120 seconds.

| Build | Thread model | Options | Result |
|---|---|---|---|
| official | Separate | none | hung 3 of 3, after 2 to 13 s |
| official | Separate | `--control` | clean, 1 of 1 |
| official | Safe (`--render-thread safe`) | none | hung 1 of 1, after about 16 s, the main thread looping on the same pair |
| debug, unchanged | Separate | `--rate=3000` | hung 3 of 3, within about 1 s |
| debug, with the `material_free` lock proposed in the issue | Separate | `--rate=3000` | clean 3 of 3 |
| debug, unchanged | Separate | `--rate=3000 --hold` | clean 3 of 3 |

Symbolized stack of the looping thread on the unchanged debug build:

```
SelfList<RendererRD::MaterialStorage::Material>::List::add   (self_list.h:46)
RendererRD::MaterialStorage::_update_queued_materials        (material_storage.cpp:2430)
RendererRD::Utilities::update_dirty_resources
RendererSceneCull::update_dirty_instances
RenderingServerDefault::_draw
RenderingServerDefault::_thread_loop
WorkerThreadPool::_process_task
```

## License

MIT, see `LICENSE`.
