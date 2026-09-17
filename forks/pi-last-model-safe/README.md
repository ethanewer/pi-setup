# pi-last-model-safe

First-party extension, no upstream. Whenever Pi changes models through `/model`,
Ctrl+P, or session restore, this extension saves that provider/model pair as the
global startup default. It also moves the model to the front of `enabledModels`,
because Pi starts a new scoped session on the first scoped model.

The extension uses Pi's `SettingsManager`, including its file lock and merge logic,
so it does not overwrite unrelated settings or race another settings write.
